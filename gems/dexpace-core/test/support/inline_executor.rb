# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The smallest thing that satisfies the executor duck type SEAM-18 requires the caller to supply:
# an object responding to #post. Running the block inline is what makes the bridge's behaviour
# deterministic in a test; phase 8's dexpace-async-thread supplies a real bounded pool.
class InlineExecutor
  def post = yield
end
