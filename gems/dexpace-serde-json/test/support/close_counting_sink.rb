# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "stringio"

# SERDE-3's "close-counting tracker", sink side: a caller-supplied stream in the shape a codec's
# #dump_to writes -- #write returning the byte count, over a BINARY StringIO -- whose #close COUNTS,
# so a suite can assert the count is exactly 0.
class CloseCountingSink
  attr_reader :close_count

  def initialize
    @io = StringIO.new(+"".b)
    @close_count = 0
  end

  # Dexpace::IO::_Sink's shape: the byte count written.
  def write(*strings) = strings.sum { |string| @io.write(string) }

  # The bytes written so far, BINARY.
  def string = @io.string

  # Counted and forwarded: the codec must never reach this.
  def close
    @close_count += 1
    @io.close
  end
end
