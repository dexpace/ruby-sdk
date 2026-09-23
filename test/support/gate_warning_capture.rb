# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# NFR-6's gate is DexpaceTestCase::FatalWarnings, PREPENDED to Warning's singleton class by phase
# 0. A prepended module sits ABOVE the singleton class's own methods, so a
# `Warning.define_singleton_method(:warn)` lands BELOW FatalWarnings and never receives the call:
# it raises nothing and captures nothing (measured on 3.2.11, 3.3.12, 3.4.10 and 4.0.6). Prepend
# order is the whole reason for this shape -- a SECOND module prepended ABOVE FatalWarnings --
# and a thread-local sink keeps the capture scoped: outside a capture block, FatalWarnings still
# raises. DexpaceTestCase is required here rather than left to the test file, so the two prepends
# land in that order however the gate suite is loaded.
#
# Named GateWarningCapture and not WarningCapture, and its prepended module GateRecordingWarnings:
# gems/dexpace-core/test/support/warning_capture.rb already defines a top-level `WarningCapture`
# with a different API (`self.record` / `self.recorded` / `self.recording?`), and this
# repository's rule is that a top-level test-support constant is unique across every suite --
# reopening one module with two incompatible APIs is the failure that rule exists to prevent
# (8a's checklist, departure 35).
#
# **This file deliberately does NOT require dexpace_test_case.** `test/gates/` is the one suite
# whose base is GateCase and not DexpaceTestCase, so FatalWarnings is not armed there -- and
# arming it from here armed it for the WHOLE test:gates process, where `Gem::Specification.load`
# on three deliberately-invalid gemspec fixtures and YARD's own load-time warnings had always
# reached `Warning.warn` harmlessly. Measured: four other gate tests went red. What this file
# needs is the recorder, not the raiser.

# The recorder, above FatalWarnings. Inert unless THIS thread is inside a capture block.
module GateRecordingWarnings
  SINK = :dexpace_gate_warning_sink

  def warn(message, category: nil)
    sink = ::Thread.current[SINK]
    return super if sink.nil?

    sink << [message, category]
    nil
  end
end
Warning.singleton_class.prepend(GateRecordingWarnings)

# Mixed into a gate test that needs to OBSERVE a warning rather than die of it.
module GateWarningCapture
  # @yield the block whose warnings are captured
  # @return [Array<Array(String, Symbol, nil)>] every [message, category] pair emitted inside
  def capture_warnings
    sink = []
    previous = ::Thread.current[GateRecordingWarnings::SINK]
    ::Thread.current[GateRecordingWarnings::SINK] = sink
    yield
    sink
  ensure
    ::Thread.current[GateRecordingWarnings::SINK] = previous
  end
end
