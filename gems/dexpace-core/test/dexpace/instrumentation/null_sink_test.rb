# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/allocation_delta"
require_relative "../../../lib/dexpace/instrumentation/null_sink"

# Exercises: OBS-1, OBS-2
#
# The default sink: one frozen instance of a private class, the shape NO_SPAN takes and for the
# same reason -- OBS-1's conformance asserts identity, and an identity needs a name. The duck type
# it implements is the whole sink contract: the four severity methods, each taking a message OR
# a block, and the four predicates. Core never requires `logger`; the proof that a stdlib Logger
# satisfies this shape is dexpace-conformance's (phase 8a).
class DexpaceInstrumentationNullSinkTest < DexpaceTestCase
  include AllocationDelta

  NULL_SINK = Dexpace::Instrumentation::NULL_SINK

  test "OBS-2: the four predicates are false, so every level reads as disabled" do
    assert_predicate(NULL_SINK, :frozen?)
    refute_predicate(NULL_SINK, :debug?)
    refute_predicate(NULL_SINK, :info?)
    refute_predicate(NULL_SINK, :warn?)
    refute_predicate(NULL_SINK, :error?)
  end

  test "OBS-1: the four methods return nil under both call forms and never evaluate the block" do
    evaluated = false
    %i[debug info warn error].each do |name|
      assert_nil(NULL_SINK.public_send(name, "message"), name.to_s)
      assert_nil(NULL_SINK.public_send(name) { evaluated = true }, name.to_s)
      assert_nil(NULL_SINK.public_send(name), name.to_s)
    end

    refute(evaluated, "a null sink must not evaluate a block it will discard")
  end

  # OBS-1's allocation clause reaches the sink too: a disabled check and a discarded write cost
  # nothing on a frozen receiver. Only Symbols cross the loop.
  test "OBS-1: a discarded write and a predicate allocate nothing per call" do
    assert_in_delta(0.0, allocations_per_call { NULL_SINK.debug? }, 0.0)
    assert_in_delta(0.0, allocations_per_call { NULL_SINK.debug(:message) }, 0.0)
  end

  test "the class behind it is a private_constant; the constant is the only public name" do
    refute_includes(Dexpace::Instrumentation.constants(false), :NullSink)
    assert_raises(::NameError) { Dexpace::Instrumentation::NullSink }
  end
end
