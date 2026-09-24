# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The ALLOWLISTED file, at the path CAUSE_WALK_ALLOWED names, so a fixture run proves the
# allowlist is joined to the gate root rather than to the process's CWD: this walk must NOT be
# reported while the sibling one is.
module Dexpace
  def self.each_cause(error)
    seen = error
    seen = seen.cause while seen.cause
    seen
  end
end
