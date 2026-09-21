# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Core's test fakes stay in core (8a's design, "Work phase 8a postponed, and who owns it now"):
# dexpace-conformance publishes its OWN doubles rather than lifting dexpace-core's test/support/
# fakes, so this is the gem's fake and not a move. A transport whose #close never flips #closed?,
# proving TransportSuite.run DETECTS a defect rather than only running assertions that pass.
class NonConformingTransport
  def call(_request, _options, _cancellation)
    raise "not exercised by the suite's own tests"
  end

  def close
    nil # deliberately never flips closed?
  end

  def closed?
    false
  end

  def owned?
    true
  end
end
