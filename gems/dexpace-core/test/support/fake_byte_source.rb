# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A _ByteSource-shaped duck over a fixed BINARY String -- #getbyte, #peek, #skip and #close, the
# four members phase 7b's line machine and reader hold their source to, and nothing else. It is
# deliberately NOT a Dexpace::IO::BufferedSource: P7-27 declares the source contract as the RBS
# interface Dexpace::SSE::_ByteSource rather than as the class, and one test per consumer drives
# this duck through it to keep that claim behavioural (phase 3b's FakeResponseBody precedent).
# Every other 7b suite uses the real BufferedSource.
class FakeByteSource
  attr_reader :getbyte_count

  def initialize(bytes)
    @bytes = bytes.b.freeze
    @pos = 0
    @getbyte_count = 0
    @closed = false
  end

  def getbyte
    @getbyte_count += 1
    return nil if @pos >= @bytes.bytesize

    byte = @bytes.getbyte(@pos)
    @pos += 1
    byte
  end

  # A non-consuming view over the remaining bytes: a fresh duck, so closing it touches nothing.
  def peek
    self.class.new(@bytes.byteslice(@pos..) || "".b)
  end

  def skip(count)
    @pos += count
    nil
  end

  def close
    @closed = true
    nil
  end

  def closed?
    @closed
  end
end
