# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# A #close-counting Response double over Dexpace::Closeable, for ASYNC-5's exactly-once orphan
# close and ASYNC-20's negative twin (a delivered response is never closed by a later cancel).
# Top level, in this gem's test/support/, because core's fakes stay in core (8a's decline) and
# no core double counts closes. Closeable's latch means a second #close never reaches #release,
# so the count is of RELEASES: "exactly once" is asserted against the latch as well as the
# caller.
class CountingResponse
  include Dexpace::Closeable

  def initialize
    @closes = 0
    @mutex = ::Thread::Mutex.new
    initialize_closeable(owned: true)
  end

  def closes
    @mutex.synchronize { @closes }
  end

  private

  def release
    @mutex.synchronize { @closes += 1 }
    nil
  end
end
