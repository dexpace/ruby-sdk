# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../percent_encoding"
require_relative "../media_type"

module Dexpace
  # HTTP-38/BODY-35's form body: always replayable, application/x-www-form-urlencoded, and encoded
  # with the "+"-for-space encoder that lives beside the RFC 3986 one rather than with the RFC 3986
  # one. Phase 1 handed this deliverable here explicitly.
  class FormBody
    include Dexpace::Body

    # The one media type every form body carries.
    MEDIA_TYPE = Dexpace::MediaType.parse("application/x-www-form-urlencoded")

    attr_reader :pairs

    # `pairs` is anything that iterates as [name, value] -- an Array of pairs or a Hash. It is
    # copied and frozen at construction, and the bytes are produced then too, so #content_length is
    # exact and a caller's later mutation cannot reach the body (HTTP-5, XCUT-15).
    def initialize(pairs)
      unless pairs.respond_to?(:map)
        raise Dexpace::InvalidArgumentError,
              "a form body takes pairs responding to #map, got #{pairs.class}"
      end

      @pairs = pairs.map do |name, value|
        [name.to_s.dup.freeze, value.to_s.dup.freeze].freeze
      end.freeze
      @bytes = Dexpace::PercentEncoding.encode_form(@pairs).b.freeze
      freeze
    end

    # Always application/x-www-form-urlencoded: the encoding is what makes this body what it is.
    def media_type
      MEDIA_TYPE
    end

    # Exact, because the bytes were produced at construction.
    def content_length
      @bytes.bytesize
    end

    def replayable?
      true
    end

    # The same encoded bytes on every write.
    def write_to(sink)
      emit_exactly(sink, @bytes)
    end

    # HTTP-46: by value, over the pairs that determine the bytes.
    def ==(other)
      other.is_a?(FormBody) && other.pairs == @pairs
    end
    alias eql? ==

    # Agrees with #==.
    def hash
      [self.class, @pairs].hash
    end
  end
end
