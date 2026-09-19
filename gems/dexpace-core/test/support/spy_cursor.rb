# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A recording wrapper over a REAL driver-made cursor: counts #call and #fork and delegates
# everything to the cursor it wraps, so a suite can assert "the step forked N times and never
# called its own cursor" (P4-39) on the cursor the step was actually handed. A test installs
# `->(request, cursor) { step.call(request, SpyCursor.new(cursor)) }` at the step's stage --
# only the driver can make a forkable cursor, and only a step installed in a pipeline is handed
# one (phase 5b's checklist, item 12, is the precedent).
class SpyCursor
  attr_reader :calls, :forks, :cursor

  def initialize(cursor)
    @cursor = cursor
    @calls = 0
    @forks = 0
  end

  def call(request = @cursor.request)
    @calls += 1
    @cursor.call(request)
  end

  def fork(state: nil)
    @forks += 1
    @cursor.fork(state: state)
  end

  def state(stage) = @cursor.state(stage)
  def request = @cursor.request
  def options = @cursor.options
  def cancellation = @cursor.cancellation
  def spent? = @cursor.spent?
  def may_fork? = @cursor.may_fork?
end
