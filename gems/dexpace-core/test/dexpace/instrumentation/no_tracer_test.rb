# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/allocation_delta"
require_relative "../../support/recording_tracer"
require "dexpace"

# CTX-20: the no-op tracer factory's method MUST be safe to invoke concurrently, and OBS-25's
# "MUST NOT allocate per call" is what the identity assertions below are for. CTX-14's "a
# per-operation tracer factory" slot and CTX-15's "no-op tracer factory"; from phase 5c, OBS-25's
# tracer protocol on NO_TRACER (Task 4), OBS-29's 1:1 clause read as binding stateful tracers
# only (P5-43) and asserted on RecordingTracerFactory, and SEAM-28's consumer: the operation
# identifier RequestContext carries is what a caller hands #tracer as `name`.
class DexpaceInstrumentationNoTracerTest < DexpaceTestCase
  NO_TRACER = Dexpace::Instrumentation::NO_TRACER
  NO_SPAN = Dexpace::Instrumentation::NO_SPAN
  FACTORY = Dexpace::Instrumentation::NO_TRACER_FACTORY

  # P4-8 and the plan's open question 1: the point of the mirrored signature is CALL
  # COMPATIBILITY, and the call shapes alone do not assert it. On Ruby 3.x a method that accepts
  # no keyword parameters receives `tracer(name: "n")` as a positional Hash, so every keyword call
  # below passes just as well against `def tracer(a = nil, b = nil)` -- the whole keyword half of
  # the gem's signature can be deleted with the call-shape assertions still green. The parameter
  # list is the discriminating assertion; the call shapes are the regression test for what
  # callers write. Read from opentelemetry-api 1.11.0's
  # lib/opentelemetry/trace/tracer_provider.rb, fetched from rubygems.org and re-read on
  # 2026-09-16, still the latest release. Boundary 10: phase 5c re-opened nothing here.
  test "the factory method mirrors opentelemetry-api 1.11.0's parameter list exactly" do
    assert_equal(
      [%i[opt deprecated_name], %i[opt deprecated_version],
       %i[key name], %i[key version], %i[key attributes],],
      FACTORY.method(:tracer).parameters,
    )
  end

  test "the factory method accepts opentelemetry-api 1.11.0's own positional and keyword shape" do
    assert_same(NO_TRACER, FACTORY.tracer)
    assert_same(NO_TRACER, FACTORY.tracer("name"))
    assert_same(NO_TRACER, FACTORY.tracer("name", "1.0"))
    assert_same(NO_TRACER, FACTORY.tracer(name: "name", version: "1.0", attributes: {}))
    assert_same(NO_TRACER, FACTORY.tracer("name", name: "other"))
  end

  test "CTX-20, OBS-30: 16 threads calling #tracer concurrently all get the same object" do
    results = Array.new(16)

    threads = Array.new(16) { |i| ::Thread.new { results[i] = FACTORY.tracer("t#{i}") } }
    threads.each(&:join)

    assert_equal(1, results.uniq.size)
    results.each { |tracer| assert_same(NO_TRACER, tracer) }
  end

  test "both singletons are frozen, and neither class is reachable by a qualified name" do
    assert_predicate(NO_TRACER, :frozen?)
    assert_predicate(FACTORY, :frozen?)
    refute_includes(Dexpace::Instrumentation.constants(false), :NoTracer)
    refute_includes(Dexpace::Instrumentation.constants(false), :NoTracerFactory)
    assert_raises(::NameError) { Dexpace::Instrumentation::NoTracerFactory }
  end

  # Phase 4 fixed the slots and phase 5c the protocol: the tracer answers exactly OBS-25's two
  # methods, and the factory still exactly the one CTX-20's embedded MUST forces.
  test "NO_TRACER defines exactly #start_span and #in_span; the factory exactly #tracer" do
    assert_equal(%i[in_span start_span], NO_TRACER.class.public_instance_methods(false).sort)
    assert_equal([:tracer], FACTORY.class.public_instance_methods(false))
  end

  # OBS-25's tracer protocol on the shipped no-op, and P5-42's signatures.
  class ProtocolTest < DexpaceTestCase
    include AllocationDelta

    FROZEN_ATTRS = { "http.request.method" => "GET" }.freeze

    test "OBS-25: #start_span returns NO_SPAN by identity under every argument shape" do
      assert_same(NO_SPAN, NO_TRACER.start_span("operation"))
      assert_same(NO_SPAN, NO_TRACER.start_span("operation", attributes: FROZEN_ATTRS))
      assert_same(NO_SPAN, NO_TRACER.start_span("operation", kind: :client, with_parent: :ctx))
    end

    test "OBS-25: #in_span yields NO_SPAN and returns the block's value" do
      yielded = nil
      result = NO_TRACER.in_span("operation", attributes: FROZEN_ATTRS, kind: :client) do |span|
        yielded = span
        :done
      end

      assert_same(NO_SPAN, yielded)
      assert_equal(:done, result)
      assert_same(NO_SPAN, NO_TRACER.in_span("operation"))
    end

    # OBS-30: nothing here rescues, so a raise inside the block is the caller's.
    test "OBS-30: an exception raised inside #in_span propagates uncaught" do
      error = assert_raises(::RuntimeError) { NO_TRACER.in_span("op") { raise "boom" } }

      assert_equal("boom", error.message)
    end

    test "P5-42: every attributes parameter is a named optional keyword, never a ** splat" do
      assert_equal(
        [%i[req name], %i[key attributes], %i[key kind], %i[key with_parent]],
        NO_TRACER.method(:start_span).parameters,
      )
      assert_equal(
        [%i[req name], %i[key attributes], %i[key kind]],
        NO_TRACER.method(:in_span).parameters,
      )
    end

    # OBS-25's conformance clause: "with no tracer installed, start/end spans in a loop and
    # assert the same singletons and no per-iteration allocation". Frozen constants only cross
    # the loop body; the block is a literal, not a Proc (support/allocation_delta.rb).
    test "OBS-25: starting and ending spans through the no-op factory allocates nothing" do
      per_call = allocations_per_call do
        tracer = FACTORY.tracer("op")
        tracer.start_span("op", attributes: FROZEN_ATTRS).finish
        tracer.in_span("op", kind: :client) { |span| span.set_attribute("k", 1) }
      end

      assert_in_delta(0.0, per_call, 0.0, "the no-op tracer path allocates per call")
    end
  end

  # OBS-29's 1:1 clause on the fake whose factory honours it (P5-43, P5-48), and SEAM-28's
  # consumer: the operation identifier is what names the tracer.
  class OperationTracerTest < DexpaceTestCase
    test "OBS-29, P5-43: the recording factory returns a fresh tracer per operation" do
      factory = Dexpace::RecordingTracerFactory.new
      first = factory.tracer("op1")
      second = factory.tracer("op2")

      refute_same(first, second)
      assert_equal(%w[op1 op2], factory.tracers.map(&:name))
    end

    # SEAM-28 (MAY): "The operation projection MAY carry a stable operation identifier for
    # instrumentation/tracing; when present it is attached to the request's context chain but
    # MUST NOT affect the assembled request's URL, headers, or body." Phase 4a's Task 7 carries
    # the identifier as RequestContext#operation_name, advisory; this is the consumer phase 5
    # was named to supply -- the identifier names the operation's tracer -- and nothing in
    # Dexpace::Instrumentation can reach a Request at all, which is the MUST NOT held
    # structurally.
    test "SEAM-28: RequestContext#operation_name is what names an operation's tracer" do
      store = Dexpace::ContextStore.new(cap: 8)
      context = Dexpace::RequestContext.build(
        bundle: Dexpace::Instrumentation::Bundle::NONE, request: :the_request,
        operation_name: "GetUser", store: store,
      )
      factory = Dexpace::RecordingTracerFactory.new
      tracer = context.bundle.tracer_factory.tracer(context.operation_name)
      recording = factory.tracer(context.operation_name)

      assert_same(NO_TRACER, tracer)
      assert_equal("GetUser", recording.name)
      assert_same(context.operation_name, recording.name)
      assert_equal(:the_request, context.request, "the identifier touched the request not at all")
    ensure
      context&.close
    end
  end
end
