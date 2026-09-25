# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"

require_relative "../model"

module Dexpace
  # URL parsing, pinned to one parser (design §3.5).
  #
  # ::URI::RFC3986_PARSER explicitly, never URI.parse and never URI::DEFAULT_PARSER: which parser
  # DEFAULT_PARSER names changed at exactly Ruby 3.4.0, which straddles this port's supported
  # range, so code written against it silently changes escaping and parsing behaviour across the
  # CI matrix without changing a line. A custom cop fails the build on either. RFC3986_PARSER has
  # been present since Ruby 3.0, so the pin costs nothing on the floor.
  #
  # A module of two functions, not a value type: the parsed URL is a URI::Generic, and wrapping
  # it would add a type every later phase has to unwrap.
  module URL
    extend self

    # The absolute URI the input denotes, parsed here and frozen through, or the HTTP-47 error
    # naming the input when it is malformed or relative.
    #
    # A URI object is re-parsed from its text rather than `dup`ed: URI::Generic#freeze is
    # shallow, `dup` shares the component Strings with the caller's object, and a String a caller
    # still holds is externally-mutable state XCUT-15 forbids a model from aliasing. Parsing
    # yields components this method owns, which it can then freeze without touching the caller's.
    def parse!(input)
      string_or_uri!(input)

      # rbs's stdlib signatures declare URI::RFC3986_Parser as an empty class, so its #parse is
      # invisible to Steep; the annotation is local to this one call rather than a reopened
      # stdlib signature shipped in sig/, which would collide the day rbs fills the class in.
      parser = ::URI::RFC3986_PARSER #: untyped
      uri = parser.parse(input.to_s) #: URI::Generic
      unless uri.absolute?
        raise InvalidArgumentError, "url #{input.to_s.inspect} is not an absolute URI (HTTP-47)"
      end

      refuse_hostless!(uri, input)

      renderable!(own(uri), input)
    rescue ::URI::Error => error
      # The Task 1 rule: a stdlib exception raised because of the argument is re-raised as the
      # SDK's argument error, naming the input, with the original left as the cause. URI::Error,
      # not only InvalidURIError: `mailto://host` raises URI::InvalidComponentError from the
      # scheme's own constructor, which escaped `rescue Dexpace::Error` until phase 10 (phase 2's
      # review R3-1).
      raise InvalidArgumentError, "url #{input.to_s.inspect} is malformed: #{error.message}"
    end

    # HTTP-46's comparison key. Ruby's URI performs no name resolution, so this is textual and
    # non-blocking by construction -- which the request equality test asserts rather than assumes.
    def external_form(uri)
      uri.to_s
    end

    # PAGE-19: RFC 3986 reference resolution of `reference` against `base`, or nil when the
    # reference cannot resolve into a URI at all -- PAGE-19 treats that as end-of-stream and not
    # as an error, and phase 7c's Dexpace::Page.next_request_from is the caller that turns the nil
    # into one. The third function of this module, added by phase 7c (P7-3) beside .parse! so
    # the parser pin lives in one file: .parse! cannot resolve, because it rejects the relative
    # reference every `<?page=2>; rel=next` is (HTTP-47), and URI.join is what the
    # Dexpace/NoUriDefaultParser cop refuses (url-and-query-encoding/08c54234). This is reference
    # resolution and never SEAM-27's base-URL composition, which Dexpace::Operation does by hand
    # because the two disagree on a query-bearing base (P2-3).
    #
    # Two things it deliberately does not do. It does not screen the result for a scheme this
    # client can dispatch: `join` hands back a `mailto:`, a host-less `http:foo` and an empty-host
    # `http:///p` as SUCCESSFUL resolutions (6b's P6-95), and whether such a target is an
    # end-of-stream or an error is the caller's decision, made once in Dexpace::Page. And it does
    # not accept a nil reference as "nothing to resolve": `join(base, nil)` raises ArgumentError,
    # not URI::InvalidURIError, so a nil here is a programming error named as such rather than a
    # silent end-of-stream.
    #
    # @param base [URI::Generic, String] the originating page's absolute URL
    # @param reference [String] the raw target, absolute or relative
    # @return [URI::Generic, nil] the resolved URI, its components frozen; nil when malformed
    # @raise [Dexpace::InvalidArgumentError] when either argument is missing or of the wrong type
    def resolve(base, reference)
      Model.required!("base", base)
      unless base.is_a?(String) || base.is_a?(::URI::Generic)
        raise InvalidArgumentError, "base must be a String or a URI, got #{base.class}"
      end
      unless Model.required!("reference", reference).is_a?(String)
        raise InvalidArgumentError, "reference must be a String, got #{reference.class}"
      end

      parser = ::URI::RFC3986_PARSER #: untyped
      own(parser.join(base.to_s, reference)) #: URI::Generic
    rescue ::URI::InvalidURIError
      nil
    end

    private

    def string_or_uri!(input)
      Model.required!("url", input)
      return if input.is_a?(String) || input.is_a?(::URI::Generic)

      raise InvalidArgumentError, "url must be a String or a URI, got #{input.class}"
    end

    # HTTP-47's rationale is failing at construction "rather than surfacing a lower-level or
    # transport-specific error later", and `URI::Generic#absolute?` is only "a scheme is present":
    # `http:` and `http:///p` parse as absolute URI::HTTPs with no host, which surfaced as whatever
    # the transport raised on a nil host. The http family is this SDK's own; which OTHER schemes a
    # transport dispatches stays the transport's knowledge (phase 1's reading), so only the http
    # family is screened for a host here (phase 10, phase 1's review round 3).
    def refuse_hostless!(uri, input)
      return unless uri.is_a?(::URI::HTTP) && (uri.host.nil? || uri.host.empty?)

      raise InvalidArgumentError, "url #{input.to_s.inspect} has no host (HTTP-47)"
    end

    # A URI whose own #to_s mutates it cannot be held frozen: URI::FTP with a `;type=` code
    # rewrites @path inside #to_s, so the frozen result raised FrozenError from every later
    # rendering -- a lower-level error, later, which is what HTTP-47 exists to prevent (phase 2's
    # review R3-2). Refused here, at construction, with the SDK's own error.
    def renderable!(uri, input)
      uri.to_s
      uri
    rescue ::FrozenError
      raise InvalidArgumentError,
            "url #{input.to_s.inspect} cannot be held as an immutable URI (HTTP-47)", cause: nil
    end

    # Freezes the URI's String components, then the URI. Only Strings: a URI also references
    # its parser, a process-global object this method leaves alone -- the uri gem freezes
    # URI::RFC3986_PARSER at definition on every supported Ruby, so nothing here needs to touch
    # it -- which is why the result is frozen AND Ractor-shareable with no global frozen from
    # here (deviation P1-13; the request and response suites assert it).
    def own(uri)
      uri.instance_variables.each do |name|
        value = uri.instance_variable_get(name)
        value.freeze if value.is_a?(String)
      end
      uri.freeze
    end
  end
end
