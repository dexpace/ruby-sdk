# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# SERDE-3's "close-counting tracker", source side: a caller-supplied stream in the shape a codec's
# #load reads -- a Dexpace::IO::BufferedSource over the given text, with every read forwarded --
# whose #close COUNTS rather than merely not raising, so a suite can assert the count is exactly 0
# ("even when the codec's own auto-close feature is enabled"). New in phase 7a: phase 2's FakeCodec
# is a codec, not a stream tracker, so none of core's three fakes is reused here.
class CloseCountingSource
  attr_reader :close_count

  def initialize(text)
    @inner = Dexpace::IO::BufferedSource.of_bytes(text.b)
    @close_count = 0
  end

  # The read vocabulary a codec may reach for, forwarded to the real source.
  def read_utf8(count: nil) = @inner.read_utf8(count: count)
  def read_string(encoding, count: nil) = @inner.read_string(encoding, count: count)
  def read(length = nil, outbuf = nil) = @inner.read(length, outbuf)
  def readpartial(maxlen, outbuf = nil) = @inner.readpartial(maxlen, outbuf)
  def eof? = @inner.eof?

  # Whether the codec read to EOF, which SERDE-3 requires beside the zero close count.
  def at_eof? = @inner.eof?

  # Counted and forwarded: the codec must never reach this.
  def close
    @close_count += 1
    @inner.close
  end
end
