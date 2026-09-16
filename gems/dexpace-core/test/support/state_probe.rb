# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# R11's read side: a slot probe recording cursor.state(stage) at every invocation. The write side
# is ForkingProbe with state_per_drive:, because only a pillar step may fork.
class StateProbe
  attr_reader :reads

  def initialize(stage_to_read:)
    @stage_to_read = stage_to_read
    @reads = []
  end

  def call(request, cursor)
    @reads << cursor.state(@stage_to_read)
    cursor.call(request)
  end
end
