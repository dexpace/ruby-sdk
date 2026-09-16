# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"

module Dexpace
  # A body over design §10.2's canonical representation: any object responding to #each and yielding
  # String chunks -- a Rack body, an Enumerator, an Array of literals.
  #
  # UNCONDITIONALLY SINGLE-USE, and there is deliberately no `replayable:` keyword on this class or
  # on Body.chunked (P3-19). BODY-1 permits #replayable? to be true ONLY when writing more than once
  # provably yields byte-for-byte identical output. An #each-shaped object may or may not, and a
  # keyword would let a caller ASSERT the property -- an assertion the retry, redirect and 401 paths
  # then believe (BODY-4). A caller with a genuinely repeatable source uses Body.bytes, or calls
  # #to_replayable and pays one materialisation.
  #
  # It closes nothing (BODY-8): it opened nothing, and an #each-shaped object that holds a resource
  # must expose #close and be closed by its owner.
  class ChunkedBody
    include Dexpace::Body

    attr_reader :media_type, :content_length

    def initialize(chunked, media_type: nil, content_length: -1)
      unless chunked.respond_to?(:each)
        raise Dexpace::InvalidArgumentError,
              "a chunked body takes an object responding to #each, got #{chunked.class}"
      end
      unless content_length.is_a?(::Integer) && content_length >= -1
        raise Dexpace::InvalidArgumentError,
              "content_length must be an Integer of -1 or more, got #{content_length.inspect}"
      end

      @chunked = chunked
      @media_type = media_type
      @content_length = content_length
      initialize_single_use
    end

    # Every chunk goes through #emit_exactly, which is the ingress retag (String#b, never
    # force_encoding, because a Rack body yields frozen literals) and BODY-13's short-write check.
    def write_to(sink)
      claim_single_use!
      written = 0
      @chunked.each { |chunk| written += emit_exactly(sink, chunk) }
      written
    end

    # HTTP-46 is Dexpace::Body's identity default, for StreamBody's reason: two different
    # #each-shaped objects are two different values even when they happen to yield the same bytes
    # once.
  end
end
