# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recovery_fixtures"
require_relative "../../support/recording_body"
require "dexpace"

# RECOV-4, RECOV-5, RECOV-6, RECOV-7, RECOV-8, RECOV-9, RECOV-12, RECOV-13, RECOV-14. Three lambda
# shapes, not two: a response step is Response -> Response, a recovery step is Outcome -> Outcome
# (R8 clause 3), and a suite that wrote response steps as ->(outcome) would be testing a chain
# this design does not describe. The private Ownership helper is asserted here, at its only
# call site, because a private_constant gets no suite of its own (P2-15).
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the fold
# rules here, ownership (RECOV-12, RECOV-13) and totality (RECOV-8, P4-19) below.
class DexpaceRecoveryResponseChainTest < DexpaceTestCase
  # Shared by every class below.
  module Chains
    include RecoveryFixtures

    def success(response = build_response)
      Dexpace::Outcome::Success.build(response: response)
    end

    def failure(error = ::IOError.new("transport failed"))
      Dexpace::Outcome::Failure.build(error: error)
    end

    def logging(log, tag)
      lambda { |value|
        log << tag
        value
      }
    end
  end
  include Chains

  # One recording array, so a chain that interleaved r1 c1 r2 c2 is caught, which two separate
  # order assertions would not.
  test "runs every response step, then every recovery step, in declared order (RECOV-6)" do
    log = []
    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [logging(log, :r1), logging(log, :r2)],
      recovery_steps: [logging(log, :c1), logging(log, :c2)],
    )
    initial = success

    result = chain.apply(initial)

    assert_same(initial, result)
    assert_equal(%i[r1 r2 c1 c2], log)
  end

  test "an empty chain returns its outcome by identity, for both variants" do
    chain = Dexpace::Recovery::ResponseChain.build
    outcomes = [success, failure]

    outcomes.each { |outcome| assert_same(outcome, chain.apply(outcome)) }
    assert_equal([], chain.response_steps)
    assert_equal([], chain.recovery_steps)
  end

  test "response steps are skipped entirely on a Failure, recovery steps still run (RECOV-4)" do
    log = []
    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [logging(log, :r1)],
      recovery_steps: [logging(log, :c1)],
    )
    initial = failure

    result = chain.apply(initial)

    assert_same(initial, result)
    assert_equal([:c1], log)
  end

  # A response step is Response -> Response: it is handed the response, not the outcome, and its
  # result is rewrapped. A response step therefore cannot return a Failure -- only a recovery
  # step can (RECOV-4's parenthesis).
  test "a response step is handed the response and its result is rewrapped as a Success" do
    replacement = build_response(201)
    seen = nil
    chain = Dexpace::Recovery::ResponseChain.build(response_steps: [
                                                     lambda { |response|
                                                       seen = response
                                                       replacement
                                                     },
                                                   ])
    original = build_response

    result = chain.apply(success(original))

    assert_same(original, seen)
    assert_predicate(result, :success?)
    assert_same(replacement, result.response)
  end

  # RECOV-5's hardest clause: a failure a RESPONSE step just produced by throwing is observed by
  # a recovery step registered after it (RECOV-7), and the response steps after the thrower do
  # not run.
  test "a throwing response step becomes a Failure the recovery steps observe (RECOV-5, RECOV-7)" do
    log = []
    observed = nil
    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [->(_) { raise ::StandardError, "response step threw" }, logging(log, :r2)],
      recovery_steps: [lambda { |outcome|
        observed = outcome
        outcome
      }],
    )

    result = chain.apply(success)

    assert_predicate(result, :failure?)
    assert_equal("response step threw", result.error.message)
    assert_same(result, observed)
    assert_empty(log, "no response step runs after the thrower")
  end

  # RECOV-8: wrapped into a Failure and fed to the NEXT recovery step -- never aborting the
  # remainder. Both halves in one test, because one assertion cannot cover them.
  test "a throwing recovery step becomes a Failure fed to the next recovery step (RECOV-8)" do
    observed = nil
    chain = Dexpace::Recovery::ResponseChain.build(recovery_steps: [
                                                     ->(_) { raise ::StandardError, "c1 threw" },
                                                     lambda { |outcome|
                                                       observed = outcome
                                                       outcome
                                                     },
                                                   ])

    result = chain.apply(success)

    assert_predicate(result, :failure?)
    assert_equal("c1 threw", result.error.message)
    assert_same(result, observed)
  end

  test "a recovery step may turn a Failure into a Success, which later steps and the caller see" do
    replacement = build_response(200)
    log = []
    chain = Dexpace::Recovery::ResponseChain.build(recovery_steps: [
                                                     ->(_) { success(replacement) },
                                                     logging(log, :after),
                                                   ])

    result = chain.apply(failure)

    assert_predicate(result, :success?)
    assert_same(replacement, result.response)
    assert_equal([:after], log)
  end

  # A :response transform installs as a response step by its own #call (R8 clause 4), and the
  # error it raises flows through recovery exactly like a transport error (RECOV-7).
  test "the error-mapping transform installs as a response step and its raise becomes a Failure" do
    chain = Dexpace::Recovery::ResponseChain.build(
      response_steps: [Dexpace::Recovery::ErrorMappingStep.build],
    )

    result = chain.apply(success(build_response(404, body: response_body("nope"))))

    assert_predicate(result, :failure?)
    assert_instance_of(Dexpace::ProtocolError, result.error)
    assert_equal("nope", result.error.response.body_string)
  end

  # RECOV-12 and RECOV-13: the one shared helper, asserted at its only call site.
  class OwnershipTest < DexpaceTestCase
    include Chains

    # A COUNT of 1, on #release and not on #close: RECOV-12's "exactly once".
    test "a throw with a Success in hand releases the response exactly once (RECOV-12)" do
      body = RecordingBody.new
      chain = Dexpace::Recovery::ResponseChain.build(
        response_steps: [->(_) { raise ::StandardError, "crash" }],
      )

      result = chain.apply(success(build_response(200, body: body)))

      assert_predicate(result, :failure?)
      assert_equal(1, body.release_count)
      assert_predicate(body, :closed?)
    end

    test "a throwing recovery step with a Success in hand releases the response once too" do
      body = RecordingBody.new
      chain = Dexpace::Recovery::ResponseChain.build(
        recovery_steps: [->(_) { raise ::StandardError, "crash" }],
      )

      chain.apply(success(build_response(200, body: body)))

      assert_equal(1, body.release_count)
    end

    # The error-mapping step buffers -- which closes the original -- and then raises, so the
    # chain's own RECOV-12 close is a SECOND close of an already-closed body: a no-op by
    # Closeable's latch, which is the whole licence for "exactly once" here. The only assertion
    # that would catch a chain that started bookkeeping instead.
    test "the error-mapping step's own close plus the chain's close release the body once" do
      body = RecordingBody.new("error payload")
      chain = Dexpace::Recovery::ResponseChain.build(
        response_steps: [Dexpace::Recovery::ErrorMappingStep.build],
      )

      result = chain.apply(success(build_response(500, body: body)))

      assert_predicate(result, :failure?)
      assert_equal(1, body.release_count, "buffer_bounded's close, then the latch's no-op")
      assert_equal("error payload", result.error.response.body_string)
    end

    # Verified fact 10: a bare close in an ensure would replace the primary and leave it
    # reachable only through #cause. The close error goes on the primary's trail instead, and
    # the primary is the SAME object (assert_same, never assert_equal).
    test "a close failure is attached as suppressed and never masks the primary (RECOV-12)" do
      body = Object.new
      def body.close = raise(::IOError, "close failure")
      primary = ::StandardError.new("primary crash")
      chain = Dexpace::Recovery::ResponseChain.build(response_steps: [->(_) { raise primary }])

      result = chain.apply(success(build_response(200, body: body)))

      assert_predicate(result, :failure?)
      assert_same(primary, result.error)
      trail = Dexpace.suppressed(result.error)

      assert_equal(1, trail.size)
      assert_equal("close failure", trail.first.message)
      assert_kind_of(Dexpace::Suppressible, result.error)
      refute_kind_of(Dexpace::Error, result.error)
    end

    # RECOV-12's third clause, and the one a suite that only drives the Success path misses.
    test "a Failure in hand carries no response, so a throw closes nothing" do
      body = RecordingBody.new
      response = build_response(200, body: body)
      chain = Dexpace::Recovery::ResponseChain.build(
        recovery_steps: [->(_) { raise ::StandardError, "threw with a Failure in hand" }],
      )

      result = chain.apply(failure)

      assert_predicate(result, :failure?)
      assert_equal(0, body.release_count)
      refute_predicate(response.body, :closed?)
    end

    # RECOV-13, asserted as a ZERO: a recovery step -- the only step position handed the
    # outcome and able to return a different one -- deliberately returns a substitute Success,
    # and the original's release count stays 0. The step owns what it dropped.
    test "a deliberate substitute Success leaves the original unreleased (RECOV-13)" do
      body = RecordingBody.new
      replacement = build_response(200, body: RecordingBody.new)
      chain = Dexpace::Recovery::ResponseChain.build(
        recovery_steps: [->(_) { Dexpace::Outcome::Success.build(response: replacement) }],
      )

      result = chain.apply(success(build_response(200, body: body)))

      assert_same(replacement, result.response)
      assert_equal(0, body.release_count)
      refute_predicate(body, :closed?)
    end

    test "a deliberate Success-to-Failure transform leaves the original unreleased (RECOV-13)" do
      body = RecordingBody.new
      chain = Dexpace::Recovery::ResponseChain.build(
        recovery_steps: [->(_) { Dexpace::Outcome::Failure.build(error: ::IOError.new("mine")) }],
      )

      result = chain.apply(success(build_response(200, body: body)))

      assert_predicate(result, :failure?)
      assert_equal(0, body.release_count)
    end

    test "a response step that returns a different response leaves the original unreleased" do
      body = RecordingBody.new
      chain = Dexpace::Recovery::ResponseChain.build(
        response_steps: [->(_) { build_response(201) }],
      )

      result = chain.apply(success(build_response(200, body: body)))

      assert_equal(201, result.response.status.code)
      assert_equal(0, body.release_count)
    end
  end

  # RECOV-8's totality over StandardError, RECOV-14's copies, and P4-19's three stated exceptions.
  class TotalityTest < DexpaceTestCase
    include Chains

    # RECOV-14, on both lists, by mutating the caller's arrays after construction.
    test "copies and freezes both step lists at construction (RECOV-14, P4-22)" do
      response_steps = [->(response) { response }]
      recovery_steps = [->(outcome) { outcome }]
      chain = Dexpace::Recovery::ResponseChain.build(
        response_steps: response_steps, recovery_steps: recovery_steps,
      )

      response_steps << ->(_) { raise "mutated" }
      recovery_steps << ->(_) { raise "mutated" }

      assert_equal(1, chain.response_steps.size)
      assert_equal(1, chain.recovery_steps.size)
      assert_predicate(chain.response_steps, :frozen?)
      assert_predicate(chain.recovery_steps, :frozen?)
      assert_predicate(chain.apply(success), :success?)
    end

    # The third of P4-19's exceptions: a non-Outcome ARGUMENT is a caller mistake refused at
    # the public boundary before any fold runs.
    test "apply refuses an argument that is not a Dexpace::Outcome (P4-19)" do
      chain = Dexpace::Recovery::ResponseChain.build

      assert_raises(Dexpace::InvalidArgumentError) { chain.apply("not an outcome") }
      assert_raises(Dexpace::InvalidArgumentError) { chain.apply(nil) }
    end

    # The first of P4-19's exceptions: a value that is not an Outcome arriving from a caller's
    # recovery step is an exhaustiveness defect, raised by name and never converted (R6).
    test "a recovery step returning a non-Outcome raises OutcomeError rather than a Failure" do
      ran = false
      chain = Dexpace::Recovery::ResponseChain.build(recovery_steps: [
                                                       ->(_) { "not an outcome" },
                                                       lambda { |outcome|
                                                         ran = true
                                                         outcome
                                                       },
                                                     ])

      error = assert_raises(Dexpace::OutcomeError) { chain.apply(success) }

      assert_equal(::String, error.offending_class)
      refute(ran, "the next recovery step must not see a demoted defect")
    end

    # A response step that returns something other than a Response is a caller step's mistake,
    # and it takes the same path as a throw: a Failure, the in-hand response released.
    test "a response step returning a non-Response becomes a Failure with the response released" do
      body = RecordingBody.new
      chain = Dexpace::Recovery::ResponseChain.build(response_steps: [->(_) { :not_a_response }])

      result = chain.apply(success(build_response(200, body: body)))

      assert_predicate(result, :failure?)
      assert_kind_of(Dexpace::InvalidArgumentError, result.error)
      assert_equal(1, body.release_count)
    end

    # The second of P4-19's exceptions, RETRY-25's rule: the fatal family is surfaced unchanged,
    # with no trail attached and no conversion, from either loop.
    test "the fatal family escapes both loops unconverted and untrailed" do
      chain = Dexpace::Recovery::ResponseChain.build(
        response_steps: [->(_) { raise ::NotImplementedError, "adapter" }],
      )
      recovery = Dexpace::Recovery::ResponseChain.build(
        recovery_steps: [->(_) { raise ::NoMemoryError, "simulated" }],
      )

      escaped = assert_raises(::NotImplementedError) { chain.apply(success) }

      assert_equal([], Dexpace.suppressed(escaped))
      assert_raises(::NoMemoryError) { recovery.apply(failure) }
    end

    test "build validates both lists and new is private" do
      build = Dexpace::Recovery::ResponseChain.method(:build)

      assert_raises(Dexpace::InvalidArgumentError) { build.call(response_steps: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { build.call(recovery_steps: [:nope]) }
      assert_raises(::NoMethodError) do
        Dexpace::Recovery::ResponseChain.new(response_steps: [], recovery_steps: [])
      end
    end
  end
end
