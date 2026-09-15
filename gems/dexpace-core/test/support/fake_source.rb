# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# IO-17's source-contract violation has no natural stand-in: no real Ruby stream returns 0 for a
# positive requested count. This double implements #read_into and NOTHING else, so it is exactly
# Dexpace::IO::_Source and is also what proves #write_all accepts a foreign source.
#
# Each script entry is either a String to deliver, the Integer 0 (the violation), -1 (end of
# stream), or an exception instance to raise. It records what it was asked for, so a test can
# assert the pump terminated rather than spun.
class FakeSource
  attr_reader :calls

  def initialize(*script)
    @script = script
    @calls = []
  end

  def read_into(dest, count:)
    @calls << count
    outcome = @script.shift
    return -1 if outcome.nil? || outcome == -1
    raise outcome if outcome.is_a?(::Exception)
    return 0 if outcome == 0 # rubocop:disable Style/NumericPredicate -- a scripted sentinel, not a count

    bytes = outcome.b
    dest << bytes
    bytes.bytesize
  end
end
