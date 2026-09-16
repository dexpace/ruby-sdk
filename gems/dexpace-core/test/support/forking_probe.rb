# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# The conformance fixture for PIPE-15, PIPE-16, PIPE-40 and R11's write side. It forks for EVERY
# drive including the first and never calls its own #call (P4-39), closes each superseded
# intermediate response before the next drive and returns the last one unclosed (PIPE-40), and
# writes the drive's state map into its own stage slot (R11).
#
# #stage is NOT declared. A probe hard-coding REDIRECT would be rejected by R10 row 3 the moment a
# test installed it at RETRY, which R11's assertion 4 does; the stage travels as the install-time
# argument instead, which is R10's own answer for a step that declares nothing.
class ForkingProbe
  attr_reader :drives, :closed_responses, :forks

  def initialize(times: 2, state_per_drive: nil)
    @times = times
    @state_per_drive = state_per_drive || []
    @drives = 0
    @closed_responses = []
    @forks = []
  end

  def call(request, cursor)
    last_response = nil

    @times.times do |i|
      # PIPE-40: the superseded intermediate is released before the next drive is issued, and the
      # one handed back is never closed -- close-responsibility passes outward.
      unless last_response.nil?
        @closed_responses << last_response
        Dexpace.close_quietly(last_response)
      end

      @drives += 1
      fork = cursor.fork(state: @state_per_drive[i])
      @forks << fork
      last_response = fork.call(request)
    end

    last_response
  end
end
