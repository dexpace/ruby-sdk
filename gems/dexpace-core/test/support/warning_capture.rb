# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Records a Kernel#warn instead of letting the shared test case raise on it.
#
# Phase 0's DexpaceTestCase prepends a module to Warning's singleton class that raises, so a
# warning fails the test that triggered it. SEAM-8 requires core to emit a warning, so exactly one
# test needs to observe one without failing. Prepending this module *after* phase 0's puts it ahead
# in the ancestor chain, so a recorded warning never reaches the raiser and an unrecorded one still
# does -- verified on 3.2.11, 3.4.10 and 4.0.6.
#
# This replaces the design's "adds the first entry to phase 0's warning allowlist": it is scoped to
# one block rather than to a message pattern for the life of the suite, and it needs no knowledge
# of phase 0's allowlist API (deviation P2-12).
module WarningCapture
  def self.recorded = @recorded ||= []

  def self.recording? = @recording

  # @return [Array<String>] the warnings emitted inside the block
  def self.record
    @recording = true
    recorded.clear
    yield
    recorded.dup
  ensure
    @recording = false
  end

  def warn(message, category: nil)
    return WarningCapture.recorded << message if WarningCapture.recording?

    super
  end
end

Warning.singleton_class.prepend(WarningCapture)
