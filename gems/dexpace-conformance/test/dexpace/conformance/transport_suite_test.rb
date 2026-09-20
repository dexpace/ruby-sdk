# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/non_conforming_transport"
require "dexpace/conformance"

# The runner (8a's R7): every assertion is run in a fresh TransportCase, its raise mapped onto one
# of five statuses, its case torn down whatever happened, and a waived id never run at all. The
# `assertions:` keyword is how these tests hand in three assertions of their own -- no `.stub`, so
# no fence here needs `minitest/mock` (docs/first-release.md's Minitest 6 entry) -- and how the
# Minitest driver test hands in a fake suite. Two nested classes under Metrics/ClassLength (6c's
# shape): the outcomes, and the three driver keywords.
module DexpaceConformanceTransportSuiteTest
  TransportSuite = Dexpace::Conformance::TransportSuite
  Failure = Dexpace::Conformance::Failure
  Vacuous = Dexpace::Conformance::Vacuous

  # The assertion builder and the one-call runner both classes share.
  module Running
    def assertion(id, &body)
      Dexpace::Conformance::Assertion.build(ids: [id], name: "checks #{id}", body: body)
    end

    def run_suite(*assertions, **)
      TransportSuite.run(build: ->(**_) { :t }, assertions: assertions, **)
    end
  end

  # The five statuses, the waiver and the per-assertion case.
  class OutcomesTest < DexpaceTestCase
    include Running

    test "run executes every assertion in order and returns a passing Report with the preamble" do
      order = []
      report = run_suite(assertion("A") { |_| order << :a }, assertion("B") { |_| order << :b })

      assert_predicate(report, :passed?)
      assert_equal(%i[a b], order)
      assert_equal(%i[passed passed], report.results.map(&:status))
      assert_equal(TransportSuite::PREAMBLE, report.preamble)
      assert_match(/plaintext/, report.preamble)
      assert_match(/connect timeout/, report.preamble)
    end

    test "a raised Failure lands as :failed, a Vacuous as :vacuous, anything else as :error" do
      failing = assertion("A") do |_|
        raise Failure.new("x", expected: 1, actual: 2, requirement_ids: ["A"])
      end
      vacuous = assertion("B") { |_| raise Vacuous, "no antecedent" }
      erroring = assertion("C") { |_| raise "boom" }

      report = run_suite(failing, vacuous, erroring)

      assert_equal(%i[failed vacuous error], report.results.map(&:status))
      assert_equal(["x", "no antecedent", "RuntimeError: boom"], report.results.map(&:detail))
      refute_predicate(report, :passed?)
    end

    test "waiving an assertion's id suppresses it into :waived without running the body" do
      ran = false
      waivable = assertion("A") do |_|
        ran = true
        raise "would have failed"
      end
      other = assertion("B") { |_| nil }

      report = run_suite(waivable, other, waive: ["A"])

      assert_equal(%i[waived passed], report.results.map(&:status))
      refute(ran, "a waived assertion's body must not run at all")
      assert_includes(report.to_s, "waived: A")
    end

    test "a waiver matches by requirement id, never by name" do
      two_ids = Dexpace::Conformance::Assertion.build(ids: %w[A B], name: "A", body: lambda { |_|
        raise "ran"
      },)

      assert_equal(%i[waived], run_suite(two_ids, waive: ["B"]).results.map(&:status))
      assert_equal(%i[error], run_suite(two_ids, waive: ["checks A"]).results.map(&:status))
    end

    test "a deliberately non-conforming fake transport fails the assertion that names its defect" do
      checks_close = assertion("SEAM-14") do |kase|
        transport = kase.transport
        transport.close
        unless transport.closed?
          raise Failure.new("closed? did not flip", expected: true, actual: false,
                                                    requirement_ids: ["SEAM-14"],)
        end
      end

      report = TransportSuite.run(build: lambda { |**_|
        NonConformingTransport.new
      }, assertions: [checks_close],)

      assert_equal(1, report.failures.size, "the suite must DETECT the defect, not merely run")
      assert_equal("closed? did not flip", report.failures.first.detail)
    end

    test "every assertion gets a FRESH case, torn down after it, whatever it raised" do
      cases = []
      transports = []
      build = lambda do |**_|
        t = Object.new
        t.define_singleton_method(:close) { transports << :closed }
        t
      end
      first = assertion("A") do |kase|
        cases << kase
        kase.transport
        raise "boom"
      end
      second = assertion("B") do |kase|
        cases << kase
        kase.transport
      end

      TransportSuite.run(build: build, assertions: [first, second])

      assert_equal(2, cases.uniq.size)
      assert_equal(%i[closed closed], transports)
    end

    test ".assertions is the frozen, ordered registry the default run uses" do
      assert_predicate(TransportSuite.assertions, :frozen?)
      assert_kind_of(Array, TransportSuite.assertions)
      TransportSuite.assertions.each { |a| assert_kind_of(Dexpace::Conformance::Assertion, a) }
    end
  end

  # The three keywords a driver passes (suite contract clauses 8, 9 and 11).
  class DriverKeywordsTest < DexpaceTestCase
    include Running

    # Suite contract clause 9 (8a's R16): the runner INVOKES the assertion, so a driver can put a
    # block around it -- how 8c's async driver opens a reactor for the whole assertion, the part
    # that reads a streamed response body included.
    test "around: wraps every assertion invocation and the assertion still runs inside it" do
      order = []
      wrapped = assertion("A") { |_| order << :assertion }

      report = run_suite(wrapped, around: lambda { |&blk|
        order << :before
        blk.call
        order << :after
      },)

      assert_predicate(report, :passed?)
      assert_equal(%i[before assertion after], order)
    end

    test "a Failure raised inside around: still lands as :failed; the wrapper cannot swallow it" do
      failing = assertion("A") do |_|
        raise Failure.new("x", expected: 1, actual: 2, requirement_ids: ["A"])
      end

      report = run_suite(failing, around: ->(&blk) { blk.call })

      assert_equal(1, report.failures.size)
    end

    # Clauses 8 and 11: the send primitive and the fixture factory reach every case the runner
    # builds.
    test "settle: and wire: reach the case, and the guard still refuses a direct #call" do
      seen = []
      kase_seen = nil
      probe = assertion("A") do |kase|
        kase_seen = kase
        seen << kase.settle(kase.transport, :req, :opts, :cancel)
        seen << kase.wire(script: :s)
      end

      report = run_suite(probe, settle: ->(_t, _r, _o, _c) { :settled }, wire: lambda { |script|
        [:wired, script]
      },)

      assert_predicate(report, :passed?, report.to_s)
      assert_equal([:settled, %i[wired s]], seen)
      assert_raises(ArgumentError) { kase_seen.transport.call(:r, :o, :c) }
    end
  end
end
