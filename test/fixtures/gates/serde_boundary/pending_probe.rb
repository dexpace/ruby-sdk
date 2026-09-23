# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The deliberately failing fixture for gates:serde_boundary's PENDING-empty clause (SSE-37).
#
# The list is a frozen constant of the tool, so there is no environment variable or gate root that
# can make the TASK see a non-empty one -- and without this the task's abort branch was never
# driven: a mutation that deleted the abort outright left every test green. Loaded with
# `RUBYOPT=-r<this file>`, it requires the tool first (so the task's own require_relative is a
# no-op) and prepends one row onto `.pending`. The glob matches nothing, which is exactly the
# state a pending row is in.
require_relative "../../../../tools/serde_boundary"

module SerdeBoundaryPendingProbe
  ROW = ["gems/dexpace-core/lib/dexpace/nowhere/**/*.rb",
         "a fixture row, so the task's abort branch is driven",].freeze

  def pending(root, list: nil)
    super(root, list: (list || [ROW]))
  end
end

SerdeBoundary.singleton_class.prepend(SerdeBoundaryPendingProbe)
