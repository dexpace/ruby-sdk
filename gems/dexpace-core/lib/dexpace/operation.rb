# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"
require_relative "http/method"
require_relative "http/url"
require_relative "http/query"
require_relative "http/query/builder"
require_relative "http/headers"
require_relative "http/headers/builder"
require_relative "http/request"
require_relative "http/request/builder"
require_relative "http/percent_encoding"
require_relative "error/invalid_argument_error"

module Dexpace
  # The operation-input projection seam: a frozen descriptor plus one builder method.
  #
  # SEAM-26 requires a per-operation declaration of an HTTP method, a path template with named
  # placeholders, and typed projections of inputs onto path / query / header / body, "so operation
  # arguments flow through typed projections rather than URL string surgery". No code generation is
  # implied; this is the runtime primitive a generator would target.
  #
  # `projections` maps an input key to [:path | :query | :header | :body, wire_name]. Only method
  # and template are required and projections default to empty, so a parameterless GET is the
  # default construction.
  #
  # SEAM-28's stable operation identifier is a MAY and is deferred (phase 5c, Task 4): both of
  # its halves need machinery phase 2 does not have -- the request's context chain (CTX, phase 4)
  # and a consumer for the identifier (instrumentation, phase 5).
  #
  # The member IS named `method`: SEAM-26 fixes it by name, and the shadowing of Object#method is
  # the same deliberate choice phase 1's Request makes, so the lint's "may be unexpected" is
  # answered rather than accepted.
  class Operation < ::Data.define(:method, :template, :projections) # rubocop:disable Lint/DataDefineOverride
    include Dexpace::Model

    TARGETS = %i[path query header body].freeze
    private_constant :TARGETS

    # Per-pattern timeouts, never the process-global Regexp.timeout: a library must not impose a
    # regexp budget on its host.
    PLACEHOLDER = Regexp.new("\\{([^{}]*)\\}", timeout: 1.0)
    private_constant :PLACEHOLDER

    BRACE = Regexp.new("[{}]", timeout: 1.0)
    private_constant :BRACE

    # RFC 3986 `path` with the placeholders removed: every character a pchar -- unreserved,
    # sub-delims, ":" or "@" -- or "/", and every "%" opening a two-hex-digit escape. The same
    # grammar URI::Generic#path= enforces at assembly, checked here so the failure is the SDK's own
    # argument error at construction rather than a stdlib URI::InvalidComponentError at the first
    # #build_request (SEAM-27's "resolving to a malformed URL is rejected with a context-bearing
    # error"). The set is spelled out rather than borrowed from URI: phase 1's URL is the one
    # place core reaches URI, and rbs declares its parser as an empty class.
    PATH_LITERAL = Regexp.new("\\A(?:%\\h\\h|[A-Za-z0-9\\-._~!$&'()*+,;=:@/])*\\z", timeout: 1.0)
    private_constant :PATH_LITERAL

    # RFC 3986 `query`: PATH_LITERAL's set plus "?". Phase 1's URL.parse! reaches
    # URI::Generic#query=, whose percent check is /(%\H\H)/ -- a "%" followed by two NON-hex
    # characters -- so a base query ending in a bare "%" or in "%z" is accepted at parse time;
    # the composition's "&limit=1" then puts "%&l" in front of the same check, from #query= again,
    # and a stdlib URI::InvalidURIError escapes #build_request. RFC 3986 `query` is strictly
    # tighter than that check (every "%" opens a two-hex escape, so no append can complete a
    # "%\H\H"), and the operation query is Query#encode's, which is RFC 3986 by construction; a
    # base query that passes here therefore composes without reaching the writer's raise. The
    # check runs before anything is appended, so the failure is the SDK's own argument error
    # naming the base, and a base malformed on its own is refused rather than composed into a
    # malformed URL silently when the operation query happens to be empty.
    QUERY_LITERAL = Regexp.new("\\A(?:%\\h\\h|[A-Za-z0-9\\-._~!$&'()*+,;=:@/?])*\\z", timeout: 1.0)
    private_constant :QUERY_LITERAL

    private_class_method :new

    # The validating factory every construction path goes through.
    def self.build(method:, template:, projections: {})
      new(method: method, template: template, projections: projections)
    end

    # The placeholder names in `text`, in order. Public because a generator validating a template
    # before building an Operation needs the same answer #initialize's check runs on.
    #
    # @return [Array<String>]
    def self.placeholders_in(text) = text.to_s.scan(PLACEHOLDER).flatten

    # Validation lives here rather than in a builder, because .build is public API, #with routes
    # every derivation through it, and send(:new, ...) reaches the constructor regardless. A
    # validating constructor also coerces: `method` goes through Dexpace::Method.of so a String
    # never survives as a member.
    def initialize(method:, template:, projections:)
      resolved = Dexpace::Method.of(Dexpace::Model.required!("method", method))
      text = Dexpace::Model.required!("template", template)
      raise Dexpace::InvalidArgumentError, "template must be a String" unless text.is_a?(::String)

      table = Validation.projections(Dexpace::Model.required!("projections", projections))
      Validation.template!(text, table)
      super(
        method: resolved,
        template: Dexpace::Model.frozen_string(text),
        projections: Dexpace::Model.own(table),
      )
    end

    # The template's placeholder names, in order.
    def placeholders = self.class.placeholders_in(template)

    # Assembles a Dexpace::Request against a base URL.
    #
    # @param base_url [String, URI::Generic] parsed through phase 1's Dexpace::URL.parse!, which
    #   pins URI::RFC3986_PARSER and rejects a non-absolute or malformed URL with the offending
    #   input in the message (HTTP-47)
    # @param inputs [Hash] operation arguments, keyed as the projection table is
    # @raise [Dexpace::InvalidArgumentError] a base carrying a fragment, no hierarchical part or
    #   a query that is not RFC 3986, or a projected path input with no value
    def build_request(base_url:, inputs: {})
      base = validated_base(base_url)
      builder = Dexpace::Request.builder
      builder.method = method
      builder.url = Composition.compose(base, render_path(inputs), render_query(inputs))
      builder.headers = render_headers(inputs)
      builder.body = body_input(inputs)
      builder.build
    end

    private

    # Phase 1's URL.parse! rejects the malformed and non-absolute case naming the input; the
    # three rules it does not carry are SEAM-27's. A base carrying a fragment is refused, naming
    # the base. So is one with no hierarchical part -- "mailto:x@y", "urn:isbn:123" -- because
    # there is no path to compose onto: URI::Generic#path= on such a base raises a stdlib
    # "path conflicts with opaque", which is the leak this method exists to convert. And so is
    # one whose query is not RFC 3986 -- "https://host/c?sig=100%" -- because #query= admits it
    # at parse time and refuses it once the operation query is appended (QUERY_LITERAL's note).
    def validated_base(base_url)
      base = Dexpace::URL.parse!(base_url)
      unless base.hierarchical?
        raise Dexpace::InvalidArgumentError,
              "a base URL must have a hierarchical part to compose onto: " \
              "#{Dexpace::URL.external_form(base)}"
      end
      unless base.fragment.nil?
        raise Dexpace::InvalidArgumentError,
              "a base URL must not carry a fragment: #{Dexpace::URL.external_form(base)}"
      end
      return base if QUERY_LITERAL.match?(base.query.to_s)

      raise Dexpace::InvalidArgumentError,
            "a base URL's query must be RFC 3986 -- every character a pchar, \"/\" or \"?\", " \
            "and every \"%\" opening a two-digit escape: #{Dexpace::URL.external_form(base)}"
    end

    # Each value goes through phase 1's strict RFC 3986 component encoder, whose unreserved set is
    # exactly A-Za-z0-9-._~, so a value containing "/" becomes "%2F" and cannot inject a segment.
    # That is SEAM-27's whole security property, and it is one call to a function phase 1 already
    # verified byte for byte.
    def render_path(inputs)
      encoded = {} #: Hash[String, String]
      projections.each do |key, (target, name)|
        next unless target == :path

        value = inputs[key]
        # `nil` is missing, not empty. SEAM-27 makes a placeholder with no supplied value an
        # error, and `inputs.key?` alone would let { id: nil } render "/pets/" -- a URL that is
        # well-formed, wrong, and silent. `false` is a value and survives.
        if value.nil?
          raise Dexpace::InvalidArgumentError,
                "operation input #{key.inspect} is required for path placeholder #{name.inspect}"
        end

        encoded[name] = Dexpace::PercentEncoding.encode_component(value.to_s)
      end
      template.gsub(PLACEHOLDER) { encoded.fetch(::Regexp.last_match(1).to_s) }
    end

    # SEAM-27's "the query MUST be RFC-3986 rendered" is phase 1's Query#encode, and a repeated
    # projection emits one parameter per value because Query is a pair list, not a Hash.
    def render_query(inputs)
      builder = Dexpace::Query.builder
      projections.each do |key, (target, name)|
        next unless target == :query
        next unless inputs.key?(key)

        Array(inputs.fetch(key)).each { |value| builder.add(name, value) }
      end
      builder.build.encode
    end

    # The outbound direction, so HTTP-17/HTTP-18 validation happens here rather than at the
    # transport -- a header value carrying a CRLF is rejected while the request is being assembled.
    #
    # A nil input is absent, as it is for a query projection and unlike a path placeholder: a
    # header can be left out where a placeholder cannot, and a generated client passing an unset
    # optional header as nil must not send an empty one. An empty String is a value and goes out.
    def render_headers(inputs)
      builder = Dexpace::Headers.builder
      projections.each do |key, (target, name)|
        next unless target == :header

        value = inputs[key]
        builder.add(name, value.to_s) unless value.nil?
      end
      builder.build
    end

    # SEAM-26's "the body is carried, not encoded": the input is handed to the request untouched.
    def body_input(inputs)
      found = projections.find { |_, (target, _)| target == :body }
      found.nil? ? nil : inputs[found.fetch(0)]
    end

    # SEAM-26's construction-time checks, kept apart from the descriptor for the same reason the
    # composition is: each half is reviewable on its own, and the descriptor's own body reads as
    # the contract rather than the checking. A private_constant.
    module Validation
      extend self

      # The projections table, validated pair by pair and frozen.
      def projections(projections)
        unless projections.is_a?(::Hash)
          raise Dexpace::InvalidArgumentError,
                "projections must be a Hash of input key => [target, wire name], " \
                "got #{projections.class}"
        end

        table = projections.to_h { |key, projection| [key, projection(key, projection)] }
        if table.count { |_, (target, _)| target == :body } > 1
          raise Dexpace::InvalidArgumentError, "an operation carries at most one body projection"
        end

        table
      end

      # One [target, wire name] pair, validated and frozen.
      def projection(key, projection)
        unless projection.is_a?(::Array) && projection.length == 2
          raise Dexpace::InvalidArgumentError,
                "projection #{key.inspect} must be a [target, wire name] pair, got " \
                "#{projection.inspect}"
        end

        target = target(key, projection.fetch(0))
        name = wire_name(key, projection.fetch(1))
        pair = [target, name] #: [Symbol, String]
        pair.freeze
      end

      # The target, one of the four parts a projection can name.
      def target(key, target)
        return target if target.is_a?(::Symbol) && TARGETS.include?(target)

        raise Dexpace::InvalidArgumentError,
              "projection #{key.inspect} targets #{target.inspect}; expected one of " \
              "#{TARGETS.map(&:inspect).join(", ")}"
      end

      # The wire name, a non-empty String of the model's own.
      def wire_name(key, name)
        text = name.to_s
        if text.empty?
          raise Dexpace::InvalidArgumentError, "projection #{key.inspect} has no wire name"
        end

        text.dup.freeze
      end

      # Two halves of SEAM-27's "every placeholder MUST have a supplied value", checked at
      # construction: a placeholder with no projection can never be filled, and a :path projection
      # naming no placeholder can never be used. Both are caller mistakes catchable before any
      # request exists, which is strictly stronger than catching them at assembly time.
      #
      # An empty template is legal -- SEAM-27's "an empty path leaves the base untouched".
      def template!(text, table)
        declared = placeholders(text)
        projected = table.each_value.select { |(target, _)| target == :path }.map(&:last)
        missing = declared - projected
        unless missing.empty?
          raise Dexpace::InvalidArgumentError,
                "template placeholder(s) #{missing.map(&:inspect).join(", ")} have no path " \
                "projection"
        end

        extra = projected - declared
        return if extra.empty?

        raise Dexpace::InvalidArgumentError,
              "path projection(s) #{extra.map(&:inspect).join(", ")} name no template placeholder"
      end

      # The placeholder names, once the template is known to be well-formed: every brace paired,
      # the literal text a URI path, and no placeholder empty.
      def placeholders(text)
        literal!(text)
        declared = Operation.placeholders_in(text)
        if declared.any?(&:empty?)
          raise Dexpace::InvalidArgumentError, "template has an empty placeholder: #{text}"
        end

        declared
      end

      # The template with its placeholders removed: every brace must be paired, and what is left
      # must be an RFC 3986 path. A placeholder's value is not the literal's concern -- it is
      # encoded to pchars at assembly -- but the literal text between placeholders is copied onto
      # the wire as it stands, so "/x?y", "/a b", "/pets/ü" and "/100%" are refused here, naming
      # the template, rather than surfacing as URI::InvalidComponentError from the first
      # #build_request. An already-encoded literal such as "/a%20b" is a path and passes.
      def literal!(text)
        literal = text.gsub(PLACEHOLDER, "")
        if BRACE.match?(literal)
          raise Dexpace::InvalidArgumentError, "template has an unbalanced brace: #{text}"
        end
        return if PATH_LITERAL.match?(literal)

        raise Dexpace::InvalidArgumentError,
              "template #{text.inspect} is not a URI path: outside a placeholder every " \
              "character must be a pchar or \"/\", and every \"%\" must open a two-digit escape"
      end
    end
    private_constant :Validation

    # SEAM-27's four composition rules, implemented directly and kept apart from the projections
    # so the composition is reviewable on its own (design §3 addendum A1). This is a
    # concatenation, not RFC 3986 reference resolution: verified on 3.2.11 and 4.0.6 that
    # URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets") is "https://host/pets", discarding
    # both the base path segment and the base query the requirement keeps -- which would silently
    # drop a signed-URL base's prefix and its SAS query, the exact case SEAM-27's rationale names.
    #
    # A private_constant: the rules are Operation's and nothing else composes a base URL.
    module Composition
      extend self

      # Works on a dup of the frozen base and assigns #path and #query rather than re-parsing a
      # re-rendered string, which is what keeps already-encoded octets verbatim (verified: a
      # frozen URI::Generic dups to an unfrozen copy whose writers work, and the original still
      # raises FrozenError).
      #
      # Both writers validate, and neither is rescued here: every input is checked to a grammar
      # at least as tight as the writer's before this runs. #path= refuses anything outside RFC
      # 3986 `path-absolute` -- the base path is the parser's own (a `segment` list, the same
      # set), the operation path is PATH_LITERAL literal plus encode_component values, and one
      # "/" joins them. #query= refuses a "%\H\H" -- the base query is QUERY_LITERAL, the
      # operation query is Query#encode, and the "&" between them can complete no escape. A
      # rescue would be a line no test can reach.
      def compose(base, path, query)
        composed = base.dup
        composed.path = compose_path(base.path.to_s, path)
        composed.query = compose_query(base.query.to_s, query)
        composed.freeze
      end

      # A trailing slash normalises to exactly one separator; an empty operation path leaves the
      # base untouched.
      def compose_path(base_path, operation_path)
        return base_path if operation_path.empty?

        "#{base_path.sub(%r{/+\z}, "")}/#{operation_path.sub(%r{\A/+}, "")}"
      end

      # An existing base query is preserved with the operation query appended after it, its
      # dangling separator dropped; either side empty yields the other.
      def compose_query(base_query, operation_query)
        base = base_query.sub(/&+\z/, "")
        return (operation_query.empty? ? nil : operation_query) if base.empty?
        return base if operation_query.empty?

        "#{base}&#{operation_query}"
      end
    end
    private_constant :Composition
  end
end
