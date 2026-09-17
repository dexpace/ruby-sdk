# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fiber_storage_facts"
require_relative "../../support/recording_span"
require "dexpace"

# OBS-22, OBS-25, P5-45, P5-46, P5-47, P5-49: the scope handle, the cached-singleton NO_SCOPE,
# and the branchless per-key restore of the two diagnostic keys (5b's constants, spelled once).
# The current-span slot key is a private_constant of scope.rb; the suite names it by value.
class DexpaceInstrumentationScopeTest < DexpaceTestCase
  include FiberStorageFacts

  Scope = Dexpace::Instrumentation::Scope
  NO_SCOPE = Dexpace::Instrumentation::NO_SCOPE
  TRACE_ID = Dexpace::Instrumentation::Diagnostics::TRACE_ID
  SPAN_ID = Dexpace::Instrumentation::Diagnostics::SPAN_ID
  CURRENT_SPAN = :"dexpace.current_span"

  # testing/4ef070df: every test runs alone, in any order. A test that leaves a current span or a
  # trace.id set poisons every later test in the same fiber -- order-dependent, and therefore a
  # failure that does not reproduce.
  def teardown
    ::Fiber[CURRENT_SPAN] = nil
    ::Fiber[TRACE_ID] = nil
    ::Fiber[SPAN_ID] = nil
    super
  end

  test "OBS-25: NO_SCOPE is a frozen singleton whose #close is nil, twice, and touches no slot" do
    ::Fiber[CURRENT_SPAN] = :untouched

    assert_predicate(NO_SCOPE, :frozen?)
    assert_nil(NO_SCOPE.close)
    assert_nil(NO_SCOPE.close)
    assert_equal(:untouched, ::Fiber[CURRENT_SPAN])
    refute_includes(Dexpace::Instrumentation.constants(false), :NoScope, "a private_constant")
  end

  test "OBS-22, P5-46: Scope is a plain three-ivar class, not a Data and not a Closeable" do
    scope = Scope.build(Dexpace::RecordingSpan.new, "t", "s")

    assert_equal(3, scope.instance_variables.size)
    refute_operator(Scope, :<, ::Data)
    refute_kind_of(Dexpace::Closeable, scope)
    refute_respond_to(scope, :closed?)
    refute_respond_to(Scope, :new)
    assert_equal([:close], Scope.public_instance_methods(false))
  end

  test "OBS-22: #close restores the previous span and both diagnostic keys, idempotently" do
    previous = Dexpace::RecordingSpan.new
    ::Fiber[CURRENT_SPAN] = Dexpace::RecordingSpan.new
    ::Fiber[TRACE_ID] = "t2"
    ::Fiber[SPAN_ID] = "s2"
    scope = Scope.build(previous, "t1", "s1")

    assert_nil(scope.close)
    assert_same(previous, ::Fiber[CURRENT_SPAN])
    assert_equal("t1", ::Fiber[TRACE_ID])
    assert_equal("s1", ::Fiber[SPAN_ID])

    # OBS-21's neighbouring idempotence clause is what a reader expects here: a second close
    # restores the same three values to the same three slots. Scope is deliberately NOT a
    # Dexpace::Closeable -- XCUT-13's latch is about owned resources and a scope owns nothing.
    ::Fiber[CURRENT_SPAN] = :drifted

    assert_nil(scope.close)
    assert_same(previous, ::Fiber[CURRENT_SPAN])
    assert_equal("t1", ::Fiber[TRACE_ID])
    assert_equal("s1", ::Fiber[SPAN_ID])
  end

  # A plain activation owes the span restore only: the two diagnostic keys are left exactly as
  # they were, which is the "delegate to plain current-span activation" half of OBS-23.
  test "OBS-22: a scope built for a plain activation restores the span and no diagnostic key" do
    previous = Dexpace::RecordingSpan.new
    ::Fiber[CURRENT_SPAN] = :active
    ::Fiber[TRACE_ID] = "kept"
    scope = Scope.build(previous)

    scope.close

    assert_same(previous, ::Fiber[CURRENT_SPAN])
    assert_equal("kept", ::Fiber[TRACE_ID])
    assert_diagnostic_key_unset(SPAN_ID)
  end

  # OBS-23's "or remove it if previously unset": one assignment, no branch on presence, at the
  # cost P5-49 records -- and on the 3.2 floor the removal is a nil value the per-key API reads
  # identically (support/fiber_storage_facts.rb, P5-72). Fiber[k] is nil in both states, so the
  # assertion has to look at the storage map; assert_nil alone passes an implementation that
  # left the pushed value behind only by luck.
  test "OBS-23, P5-49: a nil prior value removes the key rather than leaving the pushed value" do
    ::Fiber[TRACE_ID] = "t-pushed"
    ::Fiber[SPAN_ID] = "s-pushed"
    scope = Scope.build(Dexpace::RecordingSpan.new, nil, nil)

    scope.close

    assert_diagnostic_key_removed(TRACE_ID)
    assert_diagnostic_key_removed(SPAN_ID)
  end
end
