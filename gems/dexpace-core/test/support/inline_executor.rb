# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The smallest thing that satisfies the executor duck type SEAM-18 requires the caller to supply:
# an object responding to #post. Running the block inline is what makes the bridge's behaviour
# deterministic in a test; phase 8's dexpace-async-thread supplies a real bounded pool.
#
# Phase 4c added the count: PIPE-33 clause 2 -- the wrapped sync pipeline runs as ONE opaque unit
# on the executor -- is `assert_equal(1, executor.posts)` for a five-step pipeline, and a second
# executor double would have been the same three lines under another name. Phase 2's suites never
# read it.
class InlineExecutor
  # @return [Integer] how many blocks have been posted
  attr_reader :posts

  def initialize
    @posts = 0
  end

  def post
    @posts += 1
    yield
  end
end
