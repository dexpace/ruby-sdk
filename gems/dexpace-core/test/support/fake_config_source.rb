# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A hermetic Dexpace::_ConfigSource (CFG-11): a callable from key name to String? over a
# test-owned hash, which is CFG-11's whole point and what makes every CFG-1..CFG-10 case run
# without touching the process environment.
#
# Named FakeConfigSource and not FakeSource: gems/dexpace-core/test/support/fake_source.rb is
# phase 3a's IO-17 double (a #read_into stream), required by four body suites, and the plan's
# FakeSource would have overwritten it (phase 5a's checklist, "Deviations from the plan"). Top
# level, like every double under test/support/.
class FakeConfigSource
  # @param entries [Hash] the key -> value map; keys and values are stringified
  def initialize(entries = {})
    @entries = {}
    entries.each { |key, value| @entries[key.to_s] = value.to_s }
    @mutex = ::Thread::Mutex.new
  end

  def call(key)
    @mutex.synchronize { @entries[key.to_s] }
  end

  def [](key)
    call(key)
  end

  def []=(key, value)
    @mutex.synchronize do
      if value.nil?
        @entries.delete(key.to_s)
      else
        @entries[key.to_s] = value.to_s
      end
    end
  end
end
