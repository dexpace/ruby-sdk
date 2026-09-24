# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SEAM-12, SEAM-25, XCUT-11, XCUT-13, XCUT-22, ASYNC-3, ASYNC-15, ASYNC-16, ASYNC-17. The
# first-party driver for dexpace-conformance's ExecutorSuite (phase 9's plan Task 11), in the
# adapter gem's own test tree following 8a's placement.
#
# Three of the four factories are real SDK objects and none is a stand-in for one:
#
#   * `build:` is `Pool.build`, wired to the case's own recorder through a real
#     `Instrumentation::Logger`, because SEAM-25's event is the ONLY channel a filed executor
#     exposes a shutdown on -- without `record_events: true` an unlatched pool passes XCUT-13.
#   * `borrow:` is core's `Transport.async_over` bridge, which is Closeable with `owned: false`:
#     the SDK object that takes a caller's executor and must never shut it down (XCUT-22).
#   * `functional:` is that same bridge over an INLINE executor -- a lightweight async transport
#     that manages no lifecycle at all, which is exactly ASYNC-17's subject. The pool is not, and
#     handing the pool there would assert the opposite requirement.
#
# ASYNC-3 is WAIVED BY ID and declared `would_fail:`. It is an unsatisfied MUST (design §10.5):
# a worker blocked in an uninterruptible call cannot be released, because §8.3 bans Thread#raise,
# Thread#kill and Timeout.timeout outright. The assertion is written to FAIL rather than to be
# absent, and the waiver prints `waived (would fail): ASYNC-3` -- never passed and never vacuous.
# `assertion_would_fail` below runs it UNWAIVED and asserts it really does fail, so the waiver
# cannot outlive the limitation it records.
require_relative "../../../test_helper"
require "dexpace/async/thread"
require "dexpace/conformance"

# The pool's run of the shared executor suite: one generated test per assertion, plus the
# report-level checks the waiver rests on.
class DexpaceAsyncThreadConformanceTest < DexpaceTestCase
  Conformance = Dexpace::Conformance
  SUITE = Conformance::ExecutorSuite
  Pool = Dexpace::Async::Thread::Pool

  # Four workers: enough for SEAM-12's sixteen concurrent posts to interleave, small enough that a
  # leaked pool is obvious in the thread count DexpaceTestCase's teardown takes.
  SIZE = 4
  # The one unsatisfied MUST this suite carries, waived by ID in the first-party build.
  UNSATISFIED = "ASYNC-3"

  # A resource-free executor: it runs the unit on the caller's thread and owns nothing, so the
  # bridge over it is the lightweight implementation ASYNC-17 says needs no lifecycle management.
  class PoolInlineExecutor
    # @yield the unit of work, run inline on the caller's own thread
    # @return [nil]
    def post
      yield
      nil
    end
  end

  # A transport the bridge will accept; nothing in ASYNC-17 reaches it, and it is never dispatched.
  class PoolIdleTransport
    # @return [nil] the transport seam's three positionals, so Registry.callable? holds
    def call(_request, _options, _cancellation) = nil
  end

  SUITE.assertions.each_with_index do |assertion, index|
    define_method(format("test_%<n>02d_%<name>s", n: index,
                                                  name: assertion.name.gsub(/\W+/, "_"),)) do
      drive(assertion)
    end
  end

  test "the suite reports no failure, no error and no unaccepted MUST-level vacuity" do
    report = SUITE.run(**suite_arguments)

    assert_empty(report.failures.map { |result| described(result) })
    assert_empty(report.errors.map { |result| described(result) })
    assert_empty(report.blocking_vacuities.map { |result| result.assertion.ids.join(", ") })
    assert_predicate(report, :passed?)
  end

  # The waiver is a claim about the port, so it is measured rather than asserted by description:
  # ASYNC-3 is waived above because it FAILS, and this runs the same assertion with no waiver and
  # requires that failure. The day an interruptible wait exists, this goes red and the waiver goes.
  test "the waived MUST really fails, which is what makes waiving it a record and not a hole" do
    report = SUITE.run(**case_arguments, waive: [], would_fail: [])

    failed = report.failures.map { |result| result.assertion.ids }.flatten

    assert_includes(failed, UNSATISFIED,
                    "ASYNC-3 no longer fails; the waiver and §10.5's entry are now stale",)
  end

  # Design R5: the waived MUST is rendered as a waiver that names the failure, never as a pass.
  test "the report prints the unsatisfied MUST as waived (would fail), never as passed" do
    rendered = SUITE.run(**suite_arguments).to_s

    assert_includes(rendered, "waived (would fail): #{UNSATISFIED}")
  end

  private

  def described(result) = "#{result.assertion.ids.join(", ")}: #{result.detail}"

  def drive(assertion)
    return skip("waived: #{UNSATISFIED}") if assertion.ids.include?(UNSATISFIED)

    assertion.call(Conformance::ExecutorCase.new(**case_arguments))
  rescue Conformance::Vacuous => error
    skip("vacuous: #{error.reason}")
  rescue Conformance::Failure => error
    flunk("#{assertion.ids.join(", ")}: #{error.message} (expected #{error.expected.inspect}, " \
          "got #{error.actual.inspect})")
  end

  def suite_arguments
    case_arguments.merge(waive: [UNSATISFIED], would_fail: [UNSATISFIED])
  end

  def case_arguments
    { build: executor_factory, borrow: borrow_factory, functional: functional_factory,
      record_events: true, }
  end

  # `events:` arrives only when the case has a recorder; a real Logger is what turns that duck-typed
  # sink into the thing Pool#close emits through, so the payload the recorder sees is the one a
  # host's own logger would see.
  def executor_factory
    lambda do |events: nil|
      logger = events.nil? ? nil : Dexpace::Instrumentation::Logger.build(sink: events)
      Pool.build(size: SIZE, logger: logger || Dexpace::Instrumentation::Logger::NULL)
    end
  end

  # Core's own borrowing holder: Closeable with `owned: false`, so its close latches and releases
  # nothing. Closing it must leave the pool accepting work, which is XCUT-22 exactly.
  def borrow_factory
    ->(pool) { Dexpace::Transport.async_over(PoolIdleTransport.new, executor: pool) }
  end

  # The same bridge over a resource-free executor: no thread, no queue, no timer, and a close that
  # is a latch and nothing else.
  def functional_factory
    lambda do |events: nil|
      _ = events
      Dexpace::Transport.async_over(PoolIdleTransport.new, executor: PoolInlineExecutor.new)
    end
  end
end
