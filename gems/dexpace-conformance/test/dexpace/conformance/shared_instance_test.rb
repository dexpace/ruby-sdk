# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# XCUT-11's structural half: per-call mutable state must not live on a shared instance, and the
# two kinds that legitimately do must be declared BY THE DRIVER. Design R8, P9-9.
class DexpaceConformanceSharedInstanceTest < DexpaceTestCase
  SharedInstance = Dexpace::Conformance::SharedInstance

  # Frozen with NO ivars -- the easy case, and the one that never reaches the branch that matters.
  class FrozenEmpty
    def initialize = freeze
  end

  # Frozen WITH ivars: the shape three real first-party subjects take
  # (Instrumentation::Redactor::DEFAULT, Instrumentation::Logger::NULL). A predicate demanding
  # `frozen? && instance_variables.empty?` condemns every one of them, which is the false
  # condemnation P9-9 exists to prevent -- so this double is the one that proves the disjunction.
  class FrozenWithState
    def initialize(policy)
      @policy = policy
      freeze
    end
  end

  # Unfrozen, with a latch and its mutex: the shape cross-cutting-invariants/89eb6533 prescribes.
  class Latched
    def initialize
      @closed = false
      @lock = Thread::Mutex.new
    end
  end

  # Per-call state on a shared instance: exactly what XCUT-11 forbids.
  class PerCallState
    def initialize = (@attempt = 0)
  end

  test "a frozen instance with no state conforms" do
    assert_nil(SharedInstance.audit(FrozenEmpty.new))
  end

  # The disjunction's first half, asserted against the exact shape the real tree carries.
  test "a frozen instance holding state conforms on frozen? alone, with nothing declared" do
    assert_nil(SharedInstance.audit(FrozenWithState.new({ "a" => 1 })))
    assert_nil(SharedInstance.audit(Dexpace::Instrumentation::Redactor::DEFAULT))
    assert_nil(SharedInstance.audit(Dexpace::Instrumentation::Logger::NULL))
  end

  test "an unfrozen latch and its mutex conform when the DRIVER declares them" do
    assert_nil(SharedInstance.audit(Latched.new, mutable: %i[@closed @lock]))
  end

  test "an undeclared mutable ivar on an unfrozen shared instance raises a Failure naming it" do
    error = assert_raises(Dexpace::Conformance::Failure) { SharedInstance.audit(PerCallState.new) }

    assert_equal([:@attempt], error.actual)
    assert_equal(["XCUT-11"], error.requirement_ids)
  end

  test "declaring only some of the state still fails on the rest" do
    assert_raises(Dexpace::Conformance::Failure) do
      SharedInstance.audit(Latched.new, mutable: [:@lock])
    end
  end

  # P9-9: an object that supplied its own exemption list could exempt the per-call state XCUT-11
  # forbids. `mutable:` is the driver's word, and the subject is never consulted.
  test "a subject declaring its own per-call state as exempt is not believed" do
    self_exempting = Class.new(PerCallState) do
      def conformance_mutable_state = [:@attempt]
    end

    assert_raises(Dexpace::Conformance::Failure) { SharedInstance.audit(self_exempting.new) }
  end

  test "the requirement ids are overridable so a seam suite can cite its own pair" do
    error = assert_raises(Dexpace::Conformance::Failure) do
      SharedInstance.audit(PerCallState.new, ids: %w[XCUT-11 SEAM-12])
    end

    assert_equal(%w[XCUT-11 SEAM-12], error.requirement_ids)
  end
end
