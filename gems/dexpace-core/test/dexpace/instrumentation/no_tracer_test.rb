# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-20: the no-op tracer factory's method MUST be safe to invoke concurrently, and OBS-25's
# "MUST NOT allocate per call" is what the identity assertions below are for. CTX-14's "a
# per-operation tracer factory" slot and CTX-15's "no-op tracer factory".
class DexpaceInstrumentationNoTracerTest < DexpaceTestCase
  # P4-8 and the plan's open question 1: the point of the mirrored signature is CALL
  # COMPATIBILITY, and the call shapes alone do not assert it. On Ruby 3.x a method that accepts
  # no keyword parameters receives `tracer(name: "n")` as a positional Hash, so every keyword call
  # below passes just as well against `def tracer(a = nil, b = nil)` -- the whole keyword half of
  # the gem's signature can be deleted with the call-shape assertions still green. The parameter
  # list is the discriminating assertion; the call shapes are the regression test for what
  # callers write. Read from opentelemetry-api 1.11.0's
  # lib/opentelemetry/trace/tracer_provider.rb, fetched from rubygems.org and re-read on
  # 2026-09-16, still the latest release.
  test "the factory method mirrors opentelemetry-api 1.11.0's parameter list exactly" do
    assert_equal(
      [%i[opt deprecated_name], %i[opt deprecated_version],
       %i[key name], %i[key version], %i[key attributes],],
      Dexpace::Instrumentation::NO_TRACER_FACTORY.method(:tracer).parameters,
    )
  end

  test "the factory method accepts opentelemetry-api 1.11.0's own positional and keyword shape" do
    factory = Dexpace::Instrumentation::NO_TRACER_FACTORY

    assert_same(Dexpace::Instrumentation::NO_TRACER, factory.tracer)
    assert_same(Dexpace::Instrumentation::NO_TRACER, factory.tracer("name"))
    assert_same(Dexpace::Instrumentation::NO_TRACER, factory.tracer("name", "1.0"))
    assert_same(
      Dexpace::Instrumentation::NO_TRACER,
      factory.tracer(name: "name", version: "1.0", attributes: {}),
    )
    assert_same(Dexpace::Instrumentation::NO_TRACER, factory.tracer("name", name: "other"))
  end

  test "CTX-20: 16 threads calling #tracer concurrently all get the same object" do
    factory = Dexpace::Instrumentation::NO_TRACER_FACTORY
    results = Array.new(16)

    threads = Array.new(16) { |i| ::Thread.new { results[i] = factory.tracer("t#{i}") } }
    threads.each(&:join)

    results.each { |tracer| assert_same(Dexpace::Instrumentation::NO_TRACER, tracer) }
  end

  test "both singletons are frozen, and neither class is reachable by a qualified name" do
    assert_predicate(Dexpace::Instrumentation::NO_TRACER, :frozen?)
    assert_predicate(Dexpace::Instrumentation::NO_TRACER_FACTORY, :frozen?)
    refute_includes(Dexpace::Instrumentation.constants(false), :NoTracer)
    refute_includes(Dexpace::Instrumentation.constants(false), :NoTracerFactory)
    assert_raises(::NameError) { Dexpace::Instrumentation::NoTracerFactory }
  end

  # Phase 4 fixed the slots and phase 5c the protocol: the tracer answers exactly OBS-25's two
  # methods, and the factory still exactly the one CTX-20's embedded MUST forces.
  test "NO_TRACER defines exactly #start_span and #in_span; the factory exactly #tracer" do
    assert_equal(
      %i[in_span start_span],
      Dexpace::Instrumentation::NO_TRACER.class.public_instance_methods(false).sort,
    )
    assert_equal(
      [:tracer],
      Dexpace::Instrumentation::NO_TRACER_FACTORY.class.public_instance_methods(false),
    )
  end
end
