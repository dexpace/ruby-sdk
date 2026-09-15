# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error"

module Dexpace
  module Serde
    # The decode half of SEAM-21's failure contract: malformed or type-mismatched input raises
    # this, from inside the rescue of the backing library's own failure so #cause is chained; a
    # genuine stream I/O error is NOT reclassified and propagates unwrapped (SEAM-21).
    class DeserializationError < Error
    end
  end
end
