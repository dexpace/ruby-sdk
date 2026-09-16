# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"

module Dexpace
  # HTTP-38/BODY-35's replayable byte-array and string body, and the simplest thing that satisfies
  # HTTP-36. Flat, and in a subdirectory, per P1-1 and 3a's Dexpace::StreamError precedent: a
  # Dexpace::Body:: namespace would want the member names File, Buffer and Response, three constants
  # the body code uses constantly, and the include-Dexpace shadow (docs/first-release.md, Blockers)
  # and P3-7 show that shadowing is silent for is_a? and case/when.
  #
  # Body.string and Body.bytes both return one of these, because HTTP-38 classifies a string and a
  # byte array identically and two classes for one behaviour is one more than the requirement asks.
  class BytesBody
    include Dexpace::Body

    attr_reader :media_type

    # The copy is INDEPENDENT and frozen: a caller that mutates the String it handed in cannot
    # change the body's bytes or its declared length.
    def initialize(bytes, media_type: nil)
      unless bytes.is_a?(::String)
        raise Dexpace::InvalidArgumentError, "bytes must be a String, got #{bytes.class}"
      end

      @bytes = bytes.b.freeze
      @media_type = media_type
      freeze
    end

    # Exact, and a byte count rather than a character count.
    def content_length
      @bytes.bytesize
    end

    def replayable?
      true
    end

    # The same frozen bytes on every write, through BODY-13's short-write check.
    def write_to(sink)
      emit_exactly(sink, @bytes)
    end

    # HTTP-46: by value, over the facts that determine the bytes. All three together, never #==
    # alone -- phase 1's Request#hash folds the body in, and a body with a value #== and an identity
    # #hash breaks the hash/eql? contract for every Request used as a Hash key. The other body's
    # bytes are reached with `send`, as phase 1's Headers#== reaches #values: RBS has no
    # `protected`, and a private reader is the honest declaration.
    def ==(other)
      other.is_a?(BytesBody) && other.content_length == content_length &&
        other.media_type == media_type && other.send(:bytes) == @bytes
    end
    alias eql? ==

    # Agrees with #==.
    def hash
      [self.class, @bytes, @media_type].hash
    end

    private

    attr_reader :bytes
  end
end
