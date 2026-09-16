# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-14's "an active span" slot and CTX-15's "a no-op span": one shared, frozen object, so
# OBS-25's "MUST NOT allocate per call" is assertable by reference identity (phase 5c gives its
# class the protocol; phase 4 fixes the object's identity).
class DexpaceInstrumentationNoSpanTest < DexpaceTestCase
  test "NO_SPAN is a single frozen instance" do
    assert_predicate(Dexpace::Instrumentation::NO_SPAN, :frozen?)
    assert_same(Dexpace::Instrumentation::NO_SPAN, Dexpace::Instrumentation::NO_SPAN)
  end

  # The object is public by identity; its class is a private_constant, so phase 5 can widen it
  # without an NFR-4 diff and nothing can build a second one.
  test "NO_SPAN's class is a private_constant, reachable by no qualified name" do
    refute_includes(Dexpace::Instrumentation.constants(false), :NoSpan)
    assert_raises(::NameError) { Dexpace::Instrumentation::NoSpan }
  end

  # Phase 4 fixes the slot and not the protocol: the object answers nothing beyond Object's own
  # surface, and the RBS interface _Span is empty on purpose.
  test "NO_SPAN responds to nothing beyond Object's own surface" do
    assert_empty(Dexpace::Instrumentation::NO_SPAN.class.public_instance_methods(false))
  end
end
