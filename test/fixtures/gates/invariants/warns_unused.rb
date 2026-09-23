# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Parsed, never required: this file's own -w diagnostic IS the input. `e` is bound and unused --
# the shape 8a filed before commit 152ec6a dropped the binding, `rescue ::StandardError => e`
# inside Adapter#dispatch, which emits "assigned but unused variable - e" on 3.2.11, 3.3.12,
# 3.4.10 and 4.0.6 when $VERBOSE is true. Nothing here names #cause or assigns a Hash ivar, so
# every gate in the invariant set must report it CLEAN; what it proves is that the scan does not
# RAISE under the warnings-fatal test case (NFR-6).
module WarnsUnused
  def self.call(pump)
    pump.head
  rescue ::StandardError => e
    pump.close
    raise
  end
end
