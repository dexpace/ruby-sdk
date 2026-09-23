# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# Appendix B.7's lifecycle half and the harness for SEAM-25's lifecycle event, proven against
# deliberately non-conforming executors.
# SEAM-12, SEAM-25, ASYNC-3, ASYNC-15, ASYNC-16, ASYNC-17, XCUT-11, XCUT-13, XCUT-22.
class DexpaceConformanceExecutorSuiteTest < DexpaceTestCase
  Suite = Dexpace::Conformance::ExecutorSuite

  # The one payload every double emits, shaped exactly as Event#emit shapes it: a Hash whose
  # Keys::EVENT entry carries the event name. The pool's two field keys are its own private
  # constants and no portable assertion reads them, so nothing else is here.
  SHUTDOWN = { Dexpace::Instrumentation::Keys::EVENT =>
                 Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN }.freeze

  # A conforming double: an inline executor whose close is latched, which drains before returning,
  # refuses work after close, and reports its shutdown the ONLY way a filed executor does -- one
  # shutdown payload into the sink the suite supplied. It deliberately defines no
  # `#shutdown_count`: no executor in this repository has one, and a double that invented one is
  # what made an earlier draft of this suite red against the real adapter.
  class FakePool
    def initialize(events: nil, owned: true)
      @events = events
      @owned = owned
      @closed = false
      @lock = Thread::Mutex.new
    end

    def post(&)
      raise "closed" if @closed

      yield
    end

    def close
      @lock.synchronize do
        return nil if @closed

        @closed = true
      end
      return nil unless @owned

      emit_shutdown
      nil
    end

    private

    def emit_shutdown
      @events&.info { SHUTDOWN }
      nil
    end
  end

  # XCUT-13's non-conforming twin: no latch, so every close runs the shutdown again.
  class UnlatchedPool < FakePool
    def close
      @closed = true
      send(:emit_shutdown)
      nil
    end
  end

  # ASYNC-16's second half, broken: it accepts work after close.
  class LeakyPool < FakePool
    def post(&) = yield
  end

  # ASYNC-17's subject: an implementation that owns nothing, so its close shuts nothing down.
  class FunctionalExecutor
    def post(&) = yield
    def close = nil
  end

  # ASYNC-17's non-conforming twin: a "functional" implementation whose close does work.
  class WorkingCloseExecutor
    def initialize(events) = (@events = events)
    def post(&) = yield

    def close
      @events&.info { SHUTDOWN }
      nil
    end
  end

  # XCUT-22's conforming holder: it closes itself and leaves the borrowed executor alone.
  class BorrowHolder
    def initialize(pool) = (@pool = pool)
    def close = nil
  end

  # XCUT-22's non-conforming twin.
  class ClosingBorrowHolder
    def initialize(pool) = (@pool = pool)
    def close = @pool.close
  end

  def statuses(report) = report.results.to_h { |r| [r.assertion.ids.first, r.status] }

  # ASYNC-3 is waived by ID here for the same reason a first-party driver waives it: no executor
  # this repository can build releases a worker blocked in an uninterruptible call (design §10.5),
  # and the suite's job is to print that as `waived (would fail)`, never as passed.
  def conforming(**over)
    defaults = { build: ->(events: nil, **_kw) { FakePool.new(events: events) },
                 borrow: ->(pool) { BorrowHolder.new(pool) },
                 functional: ->(**_kw) { FunctionalExecutor.new },
                 record_events: true, waive: ["ASYNC-3"], would_fail: ["ASYNC-3"], }
    Suite.run(**defaults, **over)
  end

  test "the suite covers B.7's lifecycle ids, ASYNC-3 among them" do
    ids = Suite.assertions.flat_map(&:ids).uniq.sort

    assert_equal(%w[ASYNC-15 ASYNC-16 ASYNC-17 ASYNC-3 SEAM-12 SEAM-25 XCUT-11 XCUT-13 XCUT-22],
                 ids,)
    assert(ids.all? { |id| Dexpace::Conformance::Levels.known?(id) })
  end

  test "a conforming executor passes every lifecycle assertion, with ASYNC-3 waived by id" do
    report = conforming

    assert_equal({ "SEAM-12" => :passed, "XCUT-13" => :passed, "XCUT-22" => :passed,
                   "ASYNC-16" => :passed, "ASYNC-17" => :passed, "SEAM-25" => :passed,
                   "ASYNC-3" => :waived, },
                 statuses(report),)
    assert_includes(report.to_s, "waived (would fail): ASYNC-3")
  end

  # Design R5: the assertion is real and it fails. An inline executor runs the blocked call on the
  # posting thread and a pool runs it on a worker; neither can release it on cancel.
  test "ASYNC-3 genuinely fails against an executor that cannot release a blocked worker" do
    report = conforming(waive: [])

    assert_equal(:failed, statuses(report)["ASYNC-3"])
    assert_match(/still blocked/, report.failures.first.detail)
  end

  test "an unlatched close fails XCUT-13 and SEAM-25" do
    report = conforming(build: ->(events: nil, **_kw) { UnlatchedPool.new(events: events) })

    assert_equal(:failed, statuses(report)["XCUT-13"])
    assert_equal(:failed, statuses(report)["SEAM-25"])
  end

  test "a holder that closes a borrowed executor fails XCUT-22" do
    report = conforming(borrow: ->(pool) { ClosingBorrowHolder.new(pool) })

    assert_equal(:failed, statuses(report)["XCUT-22"])
  end

  test "an executor accepting work after close fails ASYNC-16" do
    report = conforming(build: ->(events: nil, **_kw) { LeakyPool.new(events: events) })

    assert_equal(:failed, statuses(report)["ASYNC-16"])
  end

  test "a functional implementation whose close does work fails ASYNC-17" do
    report = conforming(functional: ->(events: nil, **_kw) { WorkingCloseExecutor.new(events) })

    assert_equal(:failed, statuses(report)["ASYNC-17"])
  end

  test "an adapter supplying no resource-free implementation makes ASYNC-17 vacuous" do
    report = conforming(functional: nil)

    assert_equal(:vacuous, statuses(report)["ASYNC-17"])
    assert_predicate(report, :passed?, "ASYNC-17 is a SHOULD, so its vacuity does not block")
  end

  # The recorder-free path, stated as a whole report: XCUT-13 and ASYNC-17 keep running on the
  # half that needs no recorder, and only SEAM-25 -- whose whole subject IS the event -- goes
  # vacuous, with XCUT-22.
  test "an adapter with no borrowing entry point and no recorder is vacuous, never failed" do
    accepted = { "XCUT-22" => "this adapter files no borrowing entry point",
                 "ASYNC-15" => "clause (b) has no subject without one",
                 "SEAM-25" => "no event recorder was supplied to this run", }
    report = conforming(borrow: nil, record_events: false, accepted_vacuous: accepted)

    assert_equal({ "SEAM-12" => :passed, "XCUT-13" => :passed, "XCUT-22" => :vacuous,
                   "ASYNC-16" => :passed, "ASYNC-17" => :passed, "SEAM-25" => :vacuous,
                   "ASYNC-3" => :waived, },
                 statuses(report),)
    assert_predicate(report, :passed?)
  end

  # Decision: acceptance is `all?` over the assertion's MUST-level IDs. XCUT-22 and ASYNC-15 are
  # BOTH MUST in appendix C, so naming one leaves the result blocking -- which is the rule doing
  # its job rather than a typo.
  test "the same run without acceptances blocks on XCUT-22 and SEAM-25, both MUSTs" do
    report = conforming(borrow: nil, record_events: false)

    refute_predicate(report, :passed?)
    assert_equal(%w[ASYNC-15 SEAM-25 XCUT-22],
                 report.blocking_vacuities.flat_map { |r| r.assertion.ids }.uniq.sort,)
  end

  test "an acceptance naming only XCUT-22 still blocks, because ASYNC-15 is a MUST too" do
    report = conforming(borrow: nil, record_events: false,
                        accepted_vacuous: { "XCUT-22" => "this adapter files no borrowing entry" },)

    refute_predicate(report, :passed?)
    assert_includes(report.blocking_vacuities.flat_map { |r| r.assertion.ids }, "ASYNC-15")
  end

  # Without a recorder, "the shutdown ran twice" is visible nowhere, so an UNLATCHED executor
  # passes XCUT-13. The suite says so in its preamble; this is the measurement behind it.
  test "without a recorder an unlatched executor passes XCUT-13, which the preamble states" do
    report = conforming(build: ->(**_kw) { UnlatchedPool.new }, record_events: false,
                        accepted_vacuous: { "SEAM-25" => "no event recorder in this run" },)

    assert_equal(:passed, statuses(report)["XCUT-13"])
    assert_includes(report.to_s, "an UNLATCHED executor passes XCUT-13")
  end
end
