# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "percent_encoding"

module Dexpace
  # An insertion-ordered, multi-value, case-sensitive query (HTTP-28 - HTTP-32).
  #
  # A list of [name, value] pairs, not a Hash: HTTP-28 needs multiple values per name with
  # insertion order preserved ACROSS names, and a value-less parameter modelled as a single
  # empty-string value distinct from an absent name, which a Hash cannot express. Names are
  # case-sensitive, so nothing here folds. The `pairs` reader is private: #entries is the one
  # public entry-set accessor.
  class Query < Data.define(:pairs)
    include Model

    private_class_method :new
    private :pairs

    # The validating factory; the list is copied and deep-frozen, never aliased.
    def self.build(pairs:)
      new(pairs: Model.own(Model.required!("pairs", pairs)))
    end

    # A builder with no pairs.
    def self.builder
      Builder.new
    end

    # HTTP-31: lenient and total, and the exact inverse of #encode for well-formed input. A nil
    # or blank query is empty, a leading "?" is tolerated, a segment with no "=" or a trailing "="
    # is an empty-string value, a stray "&" is skipped, and a malformed escape is kept raw.
    #
    # `text.b` before `strip`, `sub` and `split`, for the same reason as HeaderSyntax.trim: a
    # query string arrives from the wire and may not be valid UTF-8, and a character operation
    # on such a String raises instead of parsing it.
    def self.parse(text)
      return EMPTY if text.nil? || text.b.strip.empty?

      pairs = [] #: Array[[String, String]]
      text.b.strip.delete_prefix("?").split("&").each do |segment|
        pairs << decode_segment(segment) unless segment.empty?
      end
      pairs.empty? ? EMPTY : build(pairs: pairs)
    end

    # One "name=value" segment, both halves decoded; a segment with no "=" has an empty value.
    def self.decode_segment(segment)
      name, _equals, value = segment.partition("=")
      [PercentEncoding.decode_component(name), PercentEncoding.decode_component(value)]
    end
    private_class_method :decode_segment

    # .build is public and #with routes through it, so the shape is checked here rather than
    # trusted from Builder#build: every pair is a [name, value] pair of Strings.
    def initialize(pairs:)
      unless pairs.is_a?(Array) && pairs.all? { |pair| pair?(pair) }
        raise InvalidArgumentError, "every query pair must be a [name, value] pair of strings"
      end

      super
    end

    # HTTP-5, first tier: a fresh per-call snapshot of the distinct names, in insertion order.
    def names
      pairs.map(&:first).uniq.freeze
    end

    # HTTP-5, first tier: a fresh frozen snapshot of every [name, value] pair.
    def entries
      pairs.map { |pair| pair.dup.freeze }.freeze
    end

    # The values under a name in insertion order, or nil when the name is absent. There is no
    # stored per-name list to hand back -- the model is a pair list -- so this allocates one and
    # freezes it, which satisfies HTTP-5's MUST by the stricter route.
    def [](name)
      found = pairs.select { |pair| pair.first == name }.map(&:last)
      found.empty? ? nil : found.freeze
    end

    # Whether any pair carries the name; a value-less parameter counts (HTTP-28).
    def include?(name)
      pairs.any? { |pair| pair.first == name }
    end

    # True when no pair is carried.
    def empty?
      pairs.empty?
    end

    # HTTP-29: one occurrence per value, insertion order preserved, no leading "?", "" when empty,
    # every name and value through the strict RFC 3986 component encoder.
    def encode
      pairs.map do |name, value|
        "#{PercentEncoding.encode_component(name)}=#{PercentEncoding.encode_component(value)}"
      end.join("&")
    end
    alias to_s encode

    # HTTP-3: a builder pre-filled with a copy of every pair.
    def new_builder
      Builder.new(pairs: pairs)
    end

    # HTTP-30 states equality in terms of the encoding -- "equal iff they encode identically" --
    # and Data's generated comparison over the pair list is a different relation: two Strings
    # holding the same non-ASCII bytes under different encoding tags are not String#== yet encode
    # to the same wire query. Comparing the encodings is the requirement stated literally
    # (api-design/e4fa3438 permits the override with this comment).
    def ==(other)
      other.is_a?(Query) && encode == other.encode
    end
    alias eql? ==

    # Agrees with #==.
    def hash
      encode.hash
    end

    def pair?(pair)
      pair.is_a?(Array) && pair.length == 2 && pair.all?(String)
    end
    private :pair?

    # The canonical empty query, so "no query" allocates nothing per request.
    EMPTY = build(pairs: [])
  end
end
