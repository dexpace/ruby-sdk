# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "strscan"

require_relative "../model"
require_relative "header_syntax"

module Dexpace
  # A media type: type, subtype and parameters (HTTP-23 - HTTP-27, HTTP-53).
  #
  # Ruby ships nothing that splits parameters respecting quoted strings, splits on the first "="
  # only, strips quotes and unescapes quoted-pairs, and renders so that parse(render(x)) == x, so
  # the parser is hand-written. `.parse` normalises -- it lower-cases and unquotes -- and the
  # constructor validates the normalised invariants, so `#with(type: "TEXT")`, which routes
  # through `.build`, fails loudly rather than producing a value whose equality is no longer
  # case-insensitive.
  #
  # Every regexp here is built with a per-pattern timeout, never the process-global
  # Regexp.timeout, because a library must not impose a regexp budget on its host; and every one
  # runs only after HeaderSyntax has proven the input to be HTAB and printable ASCII, so none can
  # meet the invalid-UTF-8 String that makes a character-oriented scan raise.
  class MediaType < Data.define(:type, :subtype, :parameters)
    include Model

    private_class_method :new

    # The charsets #charset can answer with: every encoding name this Ruby knows, folded, minus
    # the four process-relative aliases that name no charset at all. "Unknown" therefore means
    # "unknown to this Ruby", which is the narrowest reading of HTTP-24's `nil` available.
    PSEUDO_CHARSETS = %w[locale external internal filesystem].freeze
    # Every encoding name this Ruby knows, folded, with the pseudo-aliases removed.
    KNOWN_CHARSETS = (Encoding.name_list - PSEUDO_CHARSETS).map(&:downcase).freeze

    # Up to the next ";": the essence, or a bare parameter value.
    UNTIL_SEPARATOR = Regexp.new("[^;]*", timeout: 1.0)
    # A parameter separator with its surrounding whitespace.
    SEPARATOR = Regexp.new(";[ \\t]*", timeout: 1.0)
    # A parameter key: everything up to the "=" that HTTP-53 requires.
    KEY = Regexp.new("[^=;]*=", timeout: 1.0)
    # A quoted-string with quoted-pairs, then any whitespace before the next separator.
    QUOTED = Regexp.new("\"(?:[^\"\\\\]|\\\\.)*\"[ \\t]*", timeout: 1.0)
    # One quoted-pair, for unescaping.
    QUOTED_PAIR = Regexp.new("\\\\(.)", timeout: 1.0)
    # The two characters #render escapes inside a quoted-string.
    TO_ESCAPE = Regexp.new("([\"\\\\])", timeout: 1.0)
    # The parser's patterns are an implementation detail, kept out of the public surface NFR-4
    # locks at the first release tag; only the charset tables are part of the contract.
    private_constant :UNTIL_SEPARATOR, :SEPARATOR, :KEY, :QUOTED, :QUOTED_PAIR, :TO_ESCAPE

    # The validating factory; `parameters` is copied and deep-frozen at construction, never
    # aliased.
    def self.build(type:, subtype:, parameters: {})
      new(type: type, subtype: subtype, parameters: parameters)
    end

    # HTTP-26: the same predicate as an outbound header value, so a media type is always
    # header-safe. It runs on the RAW input, before any character-oriented work, because a scan
    # of invalid UTF-8 raises rather than returning something this parser could reject.
    def self.parse(text)
      Model.required!("media type", text)
      raise InvalidArgumentError, "media type must be a String" unless text.is_a?(String)
      unless HeaderSyntax.valid_outbound_value?(text)
        raise InvalidArgumentError, "media type contains a byte no header value may carry (HTTP-26)"
      end

      scanner = StringScanner.new(text)
      type, subtype = parse_essence(scanner)
      parameters = {} #: Hash[String, String]
      parse_parameter(scanner, parameters) until scanner.eos?
      build(type: type, subtype: subtype, parameters: parameters)
    end

    # HTTP-53: a non-empty type, one "/", a non-empty subtype; both folded (HTTP-23).
    def self.parse_essence(scan)
      type, slash, subtype = scan.scan(UNTIL_SEPARATOR).to_s.strip.partition("/")
      malformed!(scan, "essence") if [type, slash, subtype].any?(&:empty?) || subtype.include?("/")
      [type.downcase, subtype.downcase]
    end
    private_class_method :parse_essence

    # HTTP-25 and HTTP-53: a parameter is a separator, a key, "=" and a value, stored into
    # `parameters` as parsed. Ruby evaluates the index before the assigned value, so the key is
    # scanned first.
    def self.parse_parameter(scanner, parameters)
      malformed!(scanner) unless scanner.skip(SEPARATOR)
      parameters[parse_key(scanner)] = parse_value(scanner)
    end
    private_class_method :parse_parameter

    # Split on the FIRST "=" only -- KEY stops at the first one -- and the key is required.
    def self.parse_key(scanner)
      key = scanner.scan(KEY)&.chomp("=")&.strip
      malformed!(scanner) if key.nil? || key.empty?
      key.downcase
    end
    private_class_method :parse_key

    # A quoted-string, unescaped, which must be followed by a separator or the end; or a bare
    # value, required non-empty, which may not open a quote QUOTED could not close. A `;` inside
    # the quoted form is not a separator.
    def self.parse_value(scanner)
      if (quoted = scanner.scan(QUOTED))
        malformed!(scanner) unless scanner.eos? || scanner.match?(SEPARATOR)
        return quoted.strip[1...-1].to_s.gsub(QUOTED_PAIR) { Regexp.last_match(1) }
      end

      bare = scanner.scan(UNTIL_SEPARATOR).to_s.strip
      malformed!(scanner) if bare.empty? || bare.start_with?('"')
      bare
    end
    private_class_method :parse_value

    def self.malformed!(scanner, what = "parameter")
      raise InvalidArgumentError,
            "media type #{scanner.string.inspect} has a malformed #{what} (HTTP-53)"
    end
    private_class_method :malformed!

    # `.build` validates too, and does not trust `.parse` to have done it: type and subtype
    # present, token-shaped and already folded, a `*` type only beside a `*` subtype (HTTP-27),
    # every parameter key folded and token-shaped, and every value header-safe (HTTP-26). The
    # parameters are checked before Model.own copies them, so Ractor.make_shareable never meets
    # an object it cannot copy and its TypeError never escapes `rescue Dexpace::Error`.
    def initialize(type:, subtype:, parameters:)
      validate_component!("type", type)
      validate_component!("subtype", subtype)
      if type == "*" && subtype != "*"
        raise InvalidArgumentError, "a wildcard type is only permitted as */* (HTTP-27)"
      end

      validate_parameters!(parameters)
      super(type: Model.frozen_string(type), subtype: Model.frozen_string(subtype),
            parameters: Model.own(parameters))
    end

    # HTTP-24: the charset parameter, folded, when this Ruby knows an encoding of that name; nil
    # -- never a raise -- when it is absent or unknown, so callers fall back to a default.
    def charset
      folded = parameters["charset"]&.downcase
      KNOWN_CHARSETS.include?(folded) ? folded : nil
    end

    # HTTP-25's inverse of `.parse`: a parameter value is emitted bare when it is a token and
    # quoted with `\` and `"` escaped otherwise, so parse(render(x)) == x.
    def render
      parameters.reduce("#{type}/#{subtype}") { |out, (key, val)| "#{out}; #{key}=#{quote(val)}" }
    end
    alias to_s render

    # HTTP-27: `*/*` matches everything; a wildcard subtype matches any subtype of its type;
    # parameters take no part. The operand is checked first so a caller mistake is reported as
    # the SDK's error rather than as a NoMethodError from reading `type` off it.
    def matches?(other)
      raise InvalidArgumentError, "matches? requires a MediaType" unless other.is_a?(MediaType)
      return true if type == "*"

      type == other.type && (subtype == "*" || subtype == other.subtype)
    end

    private

    def quote(value)
      HeaderSyntax.token?(value) ? value : "\"#{value.gsub(TO_ESCAPE, "\\\\\\1")}\""
    end

    def validate_component!(name, value)
      Model.required!(name, value)
      return if value.is_a?(String) && HeaderSyntax.token?(value) && value == value.downcase

      raise InvalidArgumentError, "#{name} must be a lower-case token, got #{value.inspect}"
    end

    def validate_parameters!(parameters)
      Model.required!("parameters", parameters)
      raise InvalidArgumentError, "parameters must be a Hash" unless parameters.is_a?(Hash)

      parameters.each do |key, value|
        validate_component!("parameter key", key)
        next if value.is_a?(String) && HeaderSyntax.valid_outbound_value?(value)

        raise InvalidArgumentError, "parameter #{key} carries a byte no header value may carry"
      end
    end
  end
end
