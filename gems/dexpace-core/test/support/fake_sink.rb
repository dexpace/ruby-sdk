# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A destination that implements #write and NOTHING else, so it is exactly Dexpace::IO::_Sink.
# Scriptable to return a SHORT count (the underlying-sink contract violation) and to raise partway
# through, which is what IO-27's "clears its staging buffer even on a failed primary write" needs;
# and it records every String it received in order, which is how IO-25's "the wire body MUST never
# be reduced or altered by the tap" is asserted byte for byte.
#
# Each script entry is consumed by one #write: nil for an ordinary full write, an Integer to
# report instead of the byte count, or an exception instance to raise before anything is recorded.
class FakeSink
  attr_reader :writes

  def initialize(*script)
    @script = script
    @writes = []
  end

  def written
    @writes.join.b
  end

  def write(*strings)
    payload = strings.join.b
    outcome = @script.shift
    raise outcome if outcome.is_a?(::Exception)

    @writes << payload
    return outcome if outcome.is_a?(::Integer)

    payload.bytesize
  end
end
