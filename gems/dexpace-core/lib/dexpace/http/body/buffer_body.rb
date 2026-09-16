# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"

module Dexpace
  # The product of BODY-3/HTTP-37's materialize-once and of BODY-30/HTTP-52's bounded error copy: a
  # replayable body over a Dexpace::IO::Buffer that core owns.
  #
  # It NEVER consumes its buffer. #write_to writes through a fresh non-consuming #peek view closed
  # in an ensure, which is what makes BODY-30's "readable independently and repeatably" true rather
  # than true once, and what lets BODY-28's captured buffer keep answering after a close.
  class BufferBody
    include Dexpace::Body

    attr_reader :media_type

    def initialize(buffer, media_type: nil)
      unless buffer.is_a?(Dexpace::IO::Buffer)
        raise Dexpace::InvalidArgumentError,
              "buffer must be a Dexpace::IO::Buffer, got #{buffer.class}"
      end

      @buffer = buffer
      @media_type = media_type
      freeze
    end

    # Exact: the buffer knows what it holds.
    def content_length
      @buffer.bytesize
    end

    # A FRESH non-consuming view per call, which is the difference between this and BODY-14's
    # same-handle rule: BODY-14 governs the single-use response body, and BODY-30 requires this
    # copy to be "readable independently and repeatably". Response#body_string reads through here.
    # #close is Dexpace::Body's documented no-op -- there is no transport resource behind a buffer
    # core owns, and body_string's ensure-close must leave the copy readable (BODY-30, P3-23).
    def source
      @buffer.peek
    end

    def replayable?
      true
    end

    # Every view core takes, core closes: the view is closed in an ensure, which deregisters it
    # from the parent buffer so a repeatedly written body does not grow the parent's registry
    # (3a's view registry; Task 13 measures what leaving views open costs).
    def write_to(sink)
      view = @buffer.peek
      begin
        copy_exactly(view, sink, @buffer.bytesize)
      ensure
        view.close
      end
    end

    # HTTP-46. Bytes beyond Dexpace::IO::MAX_MATERIALIZED_BYTES are compared by identity rather than
    # by value, because #snapshot refuses to materialise them (IO-9) and an equality check must not
    # be the thing that raises. #hash is over the length and media type only, which is consistent:
    # equal bodies always hash equally.
    def ==(other)
      return true if equal?(other)
      return false unless other.is_a?(BufferBody)
      return false unless media_type == other.media_type && content_length == other.content_length
      return false if content_length > Dexpace::IO::MAX_MATERIALIZED_BYTES

      @buffer.snapshot == other.send(:snapshot_bytes)
    end
    alias eql? ==

    # Agrees with #==, over the two facts an equality check reads before the bytes.
    def hash
      [self.class, @media_type, content_length].hash
    end

    private

    # Reached with `send` from #==, as phase 1's Headers#== reaches #values.
    def snapshot_bytes
      @buffer.snapshot
    end
  end
end
