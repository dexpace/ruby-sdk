# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-14's "an active span" slot and CTX-15's "a no-op span": one shared, frozen object, so
# OBS-25's "MUST NOT allocate per call" is assertable by reference identity (phase 4 fixed the
# object's identity; phase 5c gave its class OBS-21's protocol, Task 3).
class DexpaceInstrumentationNoSpanTest < DexpaceTestCase
  test "NO_SPAN is a single frozen instance" do
    assert_predicate(Dexpace::Instrumentation::NO_SPAN, :frozen?)
    assert_same(Dexpace::Instrumentation::NO_SPAN, Dexpace::Instrumentation::NO_SPAN)
  end

  # The object is public by identity; its class is a private_constant, so phase 5c widened it
  # without an NFR-4 diff and nothing can build a second one.
  test "NO_SPAN's class is a private_constant, reachable by no qualified name" do
    refute_includes(Dexpace::Instrumentation.constants(false), :NoSpan)
    assert_raises(::NameError) { Dexpace::Instrumentation::NoSpan }
  end

  # Phase 4 fixed the slot and phase 5c the protocol: exactly OBS-21's seven methods, and the
  # RBS interface _Span declares the same seven.
  test "NO_SPAN's class defines exactly OBS-21's seven methods" do
    assert_equal(
      %i[add_event context finish record_error recording? set_attribute status=],
      Dexpace::Instrumentation::NO_SPAN.class.public_instance_methods(false).sort,
    )
  end
end
