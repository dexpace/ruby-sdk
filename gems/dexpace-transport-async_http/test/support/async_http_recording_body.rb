# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "async/http"

# R13's counting double over Protocol::HTTP::Body::Readable, the native body the adapter's
# ResponseBody holds. Counting the close beats watching the socket: "the connection looked
# released" is not an assertion, and `close_count == 1` is. `#reads` counts every native `#read`,
# which is what ASYNC-21's one-read-per-demand property is asserted over.
#
# A top-level constant named for its gem (phase 8a's rule 35): `test:gems` loads every gem's
# suite into one process, and core's test/support/ already owns a bare `RecordingBody`.
class AsyncHTTPRecordingBody < Protocol::HTTP::Body::Readable
  attr_reader :close_count, :close_errors, :reads, :length

  # @param chunks [Array<String>] what successive `#read`s return before nil
  # @param length [Integer, nil] the native length, nil for unknown
  # @param raise_after [Integer, nil] a native failure raised on the read after this many chunks
  def initialize(chunks, length: nil, raise_after: nil, error: ::EOFError.new("end of file"))
    super()
    @chunks = chunks.dup
    @length = length
    @raise_after = raise_after
    @error = error
    @close_count = 0
    @close_errors = []
    @reads = 0
  end

  # @return [Integer] how many chunks are still unread
  def remaining = @chunks.size

  def read
    @reads += 1
    raise @error if @raise_after && @reads > @raise_after

    @chunks.shift
  end

  def close(error = nil)
    @close_count += 1
    @close_errors << error
    super
  end
end
