# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../http/percent_encoding"

module Dexpace
  class Page
    # PAGE-21 through PAGE-24: the verbatim query splice. Three pure functions over the RAW query
    # substring, never over a parsed model.
    #
    # The whole design of this module is PAGE-21's byte-for-byte rule: it tokenises on `&` and
    # on the FIRST `=` of each segment, copies every untargeted segment as exactly the bytes it
    # found -- a value-less flag stays value-less, `filter=a:b` keeps its bare colon, an empty
    # segment stays empty -- and decodes or encodes only the targeted parameter's name and value.
    # It never round-trips the whole query. Phase 1's Dexpace::Query and Query::Builder are
    # correct for what they are and deliberately not used here: `Query.parse(q).encode`
    # re-encodes every parameter, rewriting `filter=a:b` to `filter=a%3Ab`, which is the
    # canonicalisation PAGE-21 forbids in as many words. Ruby's own helpers are rejected by
    # measurement rather than taste: URI.decode_www_form reads `a+b` as "a b" and
    # URI.encode_www_form_component writes a space as `+`, the exact inverse of PAGE-22 in both
    # directions. The codec is phase 1's PercentEncoding -- RFC 3986 component encoding, space to
    # `%20`, a literal `+` to `%2B` and back to `+` -- and nothing new is encoded here (PAGE-22).
    #
    # Two measured facts hold the URL half up (matrix_facts_test.rb): `URI::Generic#query=` is
    # byte-transparent for every query string the pinned parser can produce -- the canonicalising
    # happens at PARSE time, before a Request#url ever reaches this module -- so `dup`, `query=`
    # and the model's re-parse round-trip the splice exactly, and every other component survives
    # untouched (PAGE-24); and `query = nil` removes the query while `query = ""` leaves a dangling
    # `?`, which is why an empty splice is normalised to nil (P7-4).
    module QueryRewriter
      extend self

      # PAGE-22's reading half: the first matching parameter's value, decoded with RFC 3986
      # semantics -- `%20` reads as a space, a literal `+` as `+`, a value-less flag as "" -- or
      # nil when the parameter is absent. The name is matched decoded, so `pa%67e` and `page` are
      # one parameter.
      #
      # @param query [String, nil] the raw query substring, without the `?`
      # @param name [String] the parameter to read
      # @return [String, nil]
      def get(query, name)
        segments(query).each do |segment|
          raw_name, raw_value = split_segment(segment)
          next unless decode(raw_name) == name

          return raw_value.nil? ? "" : decode(raw_value)
        end
        nil
      end

      # PAGE-23: replace the first existing occurrence in place, drop every later duplicate,
      # append when absent, and remove entirely when `value` is nil; order is otherwise
      # preserved and every untargeted segment is copied byte-for-byte (PAGE-21). The new
      # name and value are RFC 3986 component-encoded (PAGE-22). An empty result is nil rather
      # than "" so the URL it is spliced into carries no dangling `?` (P7-4).
      #
      # @param query [String, nil] the raw query substring, without the `?`
      # @param name [String] the parameter to set
      # @param value [String, nil] the new value; nil removes the parameter
      # @return [String, nil] the spliced query, or nil when nothing is left
      def set(query, name, value)
        replacement = value.nil? ? nil : "#{encode(name)}=#{encode(value)}"
        out, seen = splice(segments(query), name, replacement)
        out << replacement if !seen && !replacement.nil?
        out.empty? ? nil : out.join("&")
      end

      # PAGE-24: a copy of `uri` with only its query changed, through .set. Every other component
      # -- scheme, userinfo, host, port, path, fragment -- is untouched because none is visited;
      # the caller's URI, frozen or not, is never written to.
      #
      # @param uri [URI::Generic] the template's URL
      # @param name [String] the parameter to set
      # @param value [String, nil] the new value; nil removes the parameter
      # @return [URI::Generic] a fresh URI, unfrozen, for Request#with to re-parse and own
      def rewrite_url(uri, name, value)
        copy = uri.dup
        copy.query = set(copy.query, name, value)
        copy
      end

      private

      # One pass over the segments: the first match becomes `replacement` (or vanishes when it is
      # nil), every later match is dropped, everything else is copied as the bytes it was.
      #
      # @return [Array(Array<String>, Boolean)] the output segments, and whether a match was seen
      def splice(segments, name, replacement)
        out = [] #: Array[String]
        seen = false
        segments.each do |segment|
          raw_name, = split_segment(segment)
          if decode(raw_name) == name
            out << replacement unless seen || replacement.nil?
            seen = true
          else
            out << segment
          end
        end
        [out, seen]
      end

      # `split("&", -1)` keeps empty segments -- `a&&b` and a trailing `&` are bytes PAGE-21
      # preserves -- and an absent or empty query has no segments at all.
      def segments(query)
        return [] if query.nil? || query.empty?

        query.split("&", -1)
      end

      # The first `=` only: `a=b=c` is the name `a` with the value `b=c`.
      def split_segment(segment)
        index = segment.index("=")
        return [segment, nil] if index.nil?

        [segment[0, index] || "", segment[(index + 1)..] || ""]
      end

      def decode(text) = Dexpace::PercentEncoding.decode_component(text)
      def encode(text) = Dexpace::PercentEncoding.encode_component(text)
    end
  end
end
