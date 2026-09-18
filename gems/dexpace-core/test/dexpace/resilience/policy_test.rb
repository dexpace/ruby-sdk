# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/recovery_fixtures"
require_relative "../../support/cyclic_errors"
require_relative "../../support/recording_sink"
require_relative "../../support/warning_capture"

# Exercises: RETRY-1, RETRY-2, RETRY-9, RETRY-10, RETRY-11, RETRY-12, RETRY-13, RETRY-15,
# RETRY-16, RETRY-17, RETRY-18, RETRY-19, RETRY-20, RETRY-21, RETRY-22, RETRY-23, RETRY-37,
# RETRY-41, RETRY-42, RECOV-17, RECOV-20, RECOV-21, RECOV-22, RECOV-23, RECOV-24, RECOV-25,
# RECOV-26, RECOV-27, RECOV-29, RECOV-30, CFG-35, NFR-6, XCUT-6, XCUT-7, XCUT-9, P6-5, P6-10,
# P6-12, P6-60, P6-61
#
# The shared policy core: the two-branch classifier consult, the calculator, the resolver, the
# recovery-only budget and the pacing dispatcher. Split into nested classes under
# Metrics/ClassLength: classification, backoff and budgets, then the pacing parser's forms and
# its totality (RETRY-16 is a NEGATIVE suite -- every malformed input asserts nil, never
# assert_nothing_raised).
class DexpaceResiliencePolicyTest < DexpaceTestCase
  Policy = Dexpace::Resilience::Policy

  # Shared by the nested classes.
  module Fixtures
    include RecoveryFixtures

    # A retryable throwable by XCUT-6's capability, and nothing else about it: not an IOError,
    # so a concrete-type classifier would refuse it and the capability one must not.
    class RetryableByCapability < ::StandardError
      def retryable? = true
    end

    # An IOError that says it is NOT retryable: the case a concrete-type classifier gets wrong
    # in the other direction (5a's R1: StreamError is an IOError and not a transport timeout).
    class UnretryableIOError < ::IOError
      def retryable? = false
    end

    # Exception#cause is assigned by the interpreter at the raise site and cannot be set
    # through an ivar, so every cause chain here is built by actually raising.
    def wrap(inner, outer_class = ::StandardError, message = "wrapper")
      begin
        raise inner
      rescue inner.class
        raise outer_class, message
      end
    rescue outer_class => error
      error
    end

    def headers(pairs)
      builder = Dexpace::Headers.inbound_builder
      pairs.each { |name, value| builder.add(name, value) }
      builder.build
    end
  end
  include Fixtures

  test "RETRY-12 / RETRY-13: the defaults are 200 ms, x2, 8 s, 0.2 and two retries (3 sends)" do
    assert_in_delta(0.2, Policy::DEFAULT_INITIAL_DELAY)
    assert_in_delta(2.0, Policy::DEFAULT_MULTIPLIER)
    assert_in_delta(8.0, Policy::DEFAULT_MAX_DELAY)
    assert_in_delta(0.2, Policy::DEFAULT_JITTER)
    assert_equal(2, Policy::DEFAULT_MAX_RETRIES)
    assert_equal(3, Policy::DEFAULT_MAX_RETRIES + 1, "RETRY-14: three total wire sends")
  end

  test "XCUT-7: the default configurable set is {408, 429, 500, 502, 503, 504}, frozen, a subset" do
    assert_equal(::Set[408, 429, 500, 502, 503, 504], Policy::DEFAULT_RETRYABLE_STATUSES)
    assert_predicate(Policy::DEFAULT_RETRYABLE_STATUSES, :frozen?)
    Policy::DEFAULT_RETRYABLE_STATUSES.each do |code|
      assert(Dexpace::Retryability.retryable_status?(code), "#{code} is in the baked set too")
    end
    refute_includes(Policy::DEFAULT_RETRYABLE_STATUSES, 599, "the baked set is wider")
  end

  test "RETRY-21: the fixed precedence is Retry-After, the two ms variants, then the reset" do
    assert_equal(%w[Retry-After retry-after-ms x-ms-retry-after-ms X-RateLimit-Reset],
                 Policy::DEFAULT_PACING_HEADER_ORDER,)
    assert_predicate(Policy::DEFAULT_PACING_HEADER_ORDER, :frozen?)
  end

  test "RETRY-18 / RECOV-34: the ceilings are 365 days and the signed 64-bit nanosecond count" do
    assert_equal(31_536_000, Policy::MAX_PACING_DELAY_SECONDS)
    assert_equal(9_223_372_036_854_775_807, Policy::MAX_DURATION_NANOSECONDS)
  end

  test "RETRY-42 / P6-5: Policy is a frozen-constant, extend-self module with no state" do
    assert_empty(Policy.instance_variables)
    assert_kind_of(Policy, Policy, "extend self, never module_function")
    assert_equal(
      %i[backoff_delay budget_remaining cancellation? effective_max_retries pacing_delay
         retry_eligible? retryable? throwable_retryable?],
      Policy.public_instance_methods(false).sort,
    )
  end

  # RETRY-1, RETRY-2, RETRY-37, RECOV-17, CFG-35, XCUT-6, XCUT-7, XCUT-9, P6-10.
  class ClassificationTest < DexpaceTestCase
    include Fixtures

    test "RETRY-37 / XCUT-7: retry_eligible? consults the set alone; a NARROWING set narrows" do
      assert(Policy.retry_eligible?(418, set: ::Set[418]))
      refute(Policy.retry_eligible?(500, set: ::Set[418]))
      # 500 is retryable under 5a's baked classifier and still refused by a set that omits it:
      # authoritative-contains, never an intersection with the baked flag.
      assert(Dexpace::Retryability.retryable_status?(500))
      refute(Policy.retry_eligible?(500, set: ::Set[503]))
      assert(Policy.retry_eligible?(404, set: ::Set[404]), "and a set that WIDENS widens")
    end

    test "RETRY-2 / CFG-35: throwable_retryable? is the capability query, not a type match" do
      assert(Policy.throwable_retryable?(RetryableByCapability.new("reset")))
      refute(Policy.throwable_retryable?(UnretryableIOError.new("an IOError saying no")))
      refute(Policy.throwable_retryable?(Dexpace::StreamError.new("an IOError with no capability")))
      refute(Policy.throwable_retryable?(::StandardError.new("no capability")))
    end

    test "RETRY-2: the capability is found anywhere in the cause chain, nearest first" do
      wrapped = wrap(RetryableByCapability.new("inner"))

      assert_kind_of(RetryableByCapability, wrapped.cause, "the fixture is load-bearing")
      assert(Policy.throwable_retryable?(wrapped))
      assert(Policy.throwable_retryable?(wrap(wrapped, ::RuntimeError, "outer")))
      refute(Policy.throwable_retryable?(wrap(::StandardError.new("inner"))))
    end

    test "RETRY-2 / XCUT-9: a cyclic cause chain terminates, through 4b's identity-tracking walk" do
      first = CyclicErrorFixtures::CyclicPair.new("one")
      second = CyclicErrorFixtures::CyclicPair.new("two")
      first.other_cause = second
      second.other_cause = first

      refute(Policy.throwable_retryable?(first))
      refute(Policy.throwable_retryable?(CyclicErrorFixtures::SelfCause.new("self")))
    end

    test "RETRY-2: a non-Exception is refused rather than classified" do
      assert_raises(Dexpace::InvalidArgumentError) { Policy.throwable_retryable?("boom") }
    end

    test "RETRY-37: retryable? classifies a ProtocolError by the configured set alone" do
      error = Dexpace::ProtocolError.for(build_response(418))

      assert(Policy.retryable?(error, retryable_statuses: ::Set[418]))
      refute(Policy.retryable?(error, retryable_statuses: ::Set[500]))
      refute(Policy.retryable?(Dexpace::ProtocolError.for(build_response(503)),
                               retryable_statuses: ::Set[418],), "503 narrowed away",)
    end

    test "RETRY-2: retryable? classifies anything else by the capability" do
      assert(Policy.retryable?(RetryableByCapability.new("x"), retryable_statuses: ::Set[]))
      refute(Policy.retryable?(::RuntimeError.new("x"), retryable_statuses: ::Set[500]))
    end

    test "P6-10: a ProtocolError buried in a cause chain cannot answer the capability query" do
      protocol = Dexpace::ProtocolError.for(build_response(503))

      assert_predicate(protocol, :retryable_by_status?)
      refute_respond_to(protocol, :retryable?, "the baked flag is not the open capability")
      wrapped = wrap(protocol, Dexpace::PipelineError, "downstream")

      assert_same(protocol, wrapped.cause)
      refute(Policy.throwable_retryable?(wrapped))
      refute(Policy.retryable?(wrapped, retryable_statuses: ::Set[503]),
             "a configured set that ADMITS 503 still does not reach a wrapped ProtocolError " \
             "through the capability branch; the status branch needs the error itself",)
    end

    test "RETRY-23 / P6-60: cancellation? finds a CancelledError itself or anywhere in the chain" do
      cancelled = Dexpace::CancelledError.new(:token)

      assert(Policy.cancellation?(cancelled))
      assert(Policy.cancellation?(wrap(cancelled, ::IOError, "wrapped by a transport")))
      assert(Policy.cancellation?(wrap(wrap(cancelled), ::RuntimeError, "two levels up")))
      refute(Policy.cancellation?(::IOError.new("no cancellation anywhere")))
      refute(Policy.cancellation?(wrap(::StandardError.new("inner"))))
      assert_raises(Dexpace::InvalidArgumentError) { Policy.cancellation?("boom") }
    end

    test "RETRY-23 / RECOV-27: a cancellation is never retryable, whatever wraps it answers" do
      cancelled = Dexpace::CancelledError.new(:token)
      # A transport error that answers the capability and CARRIES the cancellation: the
      # capability branch alone would call it retryable; the cancellation guard runs first.
      carrier = wrap(cancelled, RetryableByCapability, "read interrupted")

      assert(Policy.throwable_retryable?(carrier), "the fixture is load-bearing: capability yes")
      refute(Policy.retryable?(carrier, retryable_statuses: ::Set[503]))
      refute(Policy.retryable?(cancelled, retryable_statuses: ::Set[503]))
      refute(Policy.throwable_retryable?(cancelled), "CancelledError answers no capability")
    end
  end

  # RETRY-9, RETRY-10, RETRY-11, RETRY-41, RECOV-20, RECOV-21, P6-12.
  class BackoffAndBudgetTest < DexpaceTestCase
    include Fixtures

    def backoff(attempt, **overrides)
      Policy.backoff_delay(
        attempt, initial_delay: 0.2, multiplier: 2.0, max_delay: 8.0, jitter: 0.0,
                 random: ::Random.new(1), **overrides,
      )
    end

    test "RETRY-9 / RECOV-21: the unjittered delay is initial * multiplier**(n - 1), capped" do
      assert_in_delta(0.2, backoff(1))
      assert_in_delta(0.4, backoff(2))
      assert_in_delta(0.8, backoff(3))
      assert_in_delta(6.4, backoff(6))
      assert_in_delta(8.0, backoff(7), 0.001, "12.8 capped to the 8.0 max")
      assert_in_delta(8.0, backoff(8))
    end

    test "RETRY-11: an attempt below 1 is refused, and the cap saturates a huge attempt" do
      assert_raises(Dexpace::InvalidArgumentError) { backoff(0) }
      assert_raises(Dexpace::InvalidArgumentError) { backoff(-1) }
      assert_raises(Dexpace::InvalidArgumentError) { backoff(1.5) }
      assert_in_delta(8.0, backoff(1_000), 0.001, "2.0**999 overflows to Infinity, never raises")
      assert_in_delta(8.0, backoff(100_000))
    end

    test "RETRY-11 / P6-53: a zero initial delay is zero at any attempt, never 0 * Infinity" do
      assert_in_delta(0.0, backoff(1, initial_delay: 0.0))
      assert_in_delta(0.0, backoff(1_025, initial_delay: 0.0), 0.001,
                      "2.0**1024 is Infinity; 0 * Inf is NaN",)
      assert_in_delta(0.0, backoff(5_000, initial_delay: 0, jitter: 1.0))
    end

    test "RETRY-9: Integer inputs are accepted and the result is always a Float" do
      assert_in_delta(0.5, backoff(2, initial_delay: 1, multiplier: 2, max_delay: 8, jitter: 0)
        .then { |d| d / 4 },)
      assert_instance_of(::Float, backoff(1, initial_delay: 1, multiplier: 1, max_delay: 1))
    end

    test "RETRY-10: jitter samples uniformly within [d(1 - j/2), d(1 + j/2)] with midpoint d" do
      random = ::Random.new(20_260_918)
      samples = Array.new(2_000) { backoff(1, initial_delay: 1.0, jitter: 0.5, random: random) }

      samples.each do |d|
        assert_operator(d, :>=, 0.75)
        assert_operator(d, :<=, 1.25)
      end
      assert_in_delta(1.0, samples.sum / samples.size, 0.02, "midpoint stays at d")
      assert_operator(samples.uniq.size, :>, 1_000, "a real draw, not a constant")
    end

    test "RETRY-10: jitter 0 returns d exactly; a degenerate sub-nanosecond spread returns d" do
      # Exact, so the deltas are tighter than the spread a draw would produce: an autocorrected
      # default delta of 0.001 would let a drawn 9.6e-13 pass for 1e-12 (the guard ran green).
      assert_in_delta(0.2, backoff(1, jitter: 0.0), 0.0)
      assert_in_delta(1e-12, backoff(1, initial_delay: 1e-12, jitter: 0.5), 0.0)
      assert_in_delta(1e-9, backoff(1, initial_delay: 1e-9, jitter: 0.5), 0.0,
                      "spread 5e-10 < 1e-9",)
      refute_in_delta(3e-9, backoff(1, initial_delay: 3e-9, jitter: 0.5), 1e-12,
                      "spread 1.5e-9 draws",)
    end

    test "RETRY-10 / RETRY-9: at the cap the band is drawn AROUND the cap: capped, then jittered" do
      random = ::Random.new(7)
      samples = Array.new(200) { backoff(50, jitter: 1.0, random: random) }

      samples.each do |d|
        assert_operator(d, :>=, 4.0)
        assert_operator(d, :<=, 12.0, "d(1 + j/2) with d = 8.0 and j = 1.0")
      end
      # The order RECOV-21 fixes: cap FIRST, then perturb. Jitter applied to the raw
      # 0.2 * 2**49 and clipped to the cap afterwards would answer exactly 8.0 every time and
      # never a sample above it, so the band's two halves are asserted, not only its bounds.
      assert_operator(samples.max, :>, 8.0, "a sample above the cap: jittered after capping")
      assert_operator(samples.min, :<, 8.0)
    end

    test "RETRY-10: a negative sample is floored at zero" do
      below_zero = ::Object.new
      def below_zero.rand(_range) = -0.5

      assert_in_delta(0.0, backoff(1, jitter: 1.0, random: below_zero))
    end
  end

  # RETRY-41, RECOV-20, P6-12: the resolver and the recovery-only budget.
  class ResolverAndBudgetTest < DexpaceTestCase
    include Fixtures

    test "RETRY-41: present-override-wins, else configured; negative clamped; zero allowed" do
      assert_equal(5, Policy.effective_max_retries(override: 5, configured: 2))
      assert_equal(0, Policy.effective_max_retries(override: 0, configured: 2), "zero: no retries")
      assert_equal(2, Policy.effective_max_retries(override: nil, configured: 2))
      assert_equal(0, Policy.effective_max_retries(override: nil, configured: 0))
      assert_equal(Policy::DEFAULT_MAX_RETRIES,
                   Policy.effective_max_retries(override: nil, configured: -1),)
    end

    test "RETRY-41: a negative or non-Integer override is validated, not silently ignored" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Policy.effective_max_retries(override: -1, configured: 2)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Policy.effective_max_retries(override: 1.5, configured: 2)
      end
    end

    test "RETRY-41 / P6-12: the clamp is logged as one WARNING config diagnostic, nothing else" do
      sink = RecordingSink.new
      logger = Dexpace::Instrumentation::Logger.build(sink: sink)

      assert_equal(2, Policy.effective_max_retries(override: nil, configured: 2, logger: logger))
      assert_equal(2, Policy.effective_max_retries(override: 9, configured: -3, logger: logger)
        .then { 2 },)
      assert_empty(sink.entries, "neither a configured nor an overridden value logs")

      Policy.effective_max_retries(override: nil, configured: -3, logger: logger)

      assert_equal([:warn], sink.entries.map(&:severity))
      payload = sink.payloads.first

      assert_equal(Dexpace::Instrumentation::Events::INSTRUMENTATION_CONFIG,
                   payload[Dexpace::Instrumentation::Keys::EVENT],)
      assert_match(/clamped/, payload[Dexpace::Instrumentation::Keys::MESSAGE])
      assert_match(/-3/, payload[Dexpace::Instrumentation::Keys::MESSAGE])
    end

    test "RETRY-41 / OBS-20: a raising sink cannot fail the resolution" do
      sink = RecordingSink.new
      def sink.warn(*) = raise("sink down")
      logger = Dexpace::Instrumentation::Logger.build(sink: sink)

      assert_equal(Policy::DEFAULT_MAX_RETRIES,
                   Policy.effective_max_retries(override: nil, configured: -1, logger: logger),)
    end

    test "RECOV-20: budget_remaining is the time REMAINING, Infinity for a zero budget" do
      assert_equal(::Float::INFINITY, Policy.budget_remaining(elapsed: 100.0, total_timeout: 0))
      assert_equal(::Float::INFINITY, Policy.budget_remaining(elapsed: 0.0, total_timeout: 0.0))
      assert_in_delta(4.0, Policy.budget_remaining(elapsed: 6.0, total_timeout: 10.0))
      assert_in_delta(-2.0, Policy.budget_remaining(elapsed: 12.0, total_timeout: 10), 0.001,
                      "negative once spent; a caller compares against remaining, never elapsed",)
      assert_instance_of(::Float, Policy.budget_remaining(elapsed: 1, total_timeout: 10))
    end
  end

  # RETRY-15, RETRY-17, RETRY-19, RETRY-21, RECOV-24, RECOV-25: the forms and the precedence.
  class PacingFormsTest < DexpaceTestCase
    include Fixtures

    ORDER = Policy::DEFAULT_PACING_HEADER_ORDER
    NOW = ::Time.utc(2026, 9, 18, 12, 0, 0)

    # No keyword parameter here on purpose: a braceless `delay("Retry-After" => "5")` would
    # otherwise be read as keywords under Ruby 3's separation.
    def delay(pairs)
      Policy.pacing_delay(headers(pairs), header_order: ORDER, now: NOW)
    end

    def delay_with(pairs, random)
      Policy.pacing_delay(headers(pairs), header_order: ORDER, now: NOW, random: random)
    end

    test "RETRY-15 / RECOV-24: Retry-After as delta-seconds, integer and fractional" do
      assert_in_delta(5.0, delay("Retry-After" => "5"))
      assert_in_delta(2.5, delay("Retry-After" => "2.5"))
      assert_in_delta(0.001, delay("Retry-After" => "0.001"), 0.00001, "sub-second honoured")
      assert_in_delta(0.0, delay("Retry-After" => "0"))
    end

    test "RETRY-15: Retry-After as an RFC 1123 HTTP-date, measured from `now`" do
      assert_in_delta(90.0, delay("Retry-After" => "Fri, 18 Sep 2026 12:01:30 GMT"))
      assert_in_delta(90.0, delay("Retry-After" => "Fri, 18 Sep 2026 12:01:30 UTC"))
    end

    test "RETRY-15 / R1: the HTTP-date form tolerates a wrong weekday and a single-digit day" do
      assert_in_delta(90.0, delay("Retry-After" => "Mon, 18 Sep 2026 12:01:30 GMT"), 0.001,
                      "wrong weekday",)
      assert_in_delta(90.0, delay("Retry-After" => "Fri, 18 sep 2026 12:01:30 gmt"), 0.001, "case")
      later = ::Time.utc(2026, 9, 1, 12, 0, 0)

      early = headers("Retry-After" => "Tue, 1 Sep 2026 12:01:00 GMT")

      assert_in_delta(60.0, Policy.pacing_delay(early, header_order: ORDER, now: later))
    end

    test "RETRY-17 / RECOV-23: a valid HTTP-date or epoch already past is ZERO, not nil" do
      assert_in_delta(0.0, delay("Retry-After" => "Sun, 06 Nov 1994 08:49:37 GMT"))
      assert_in_delta(0.0, delay("Retry-After" => "Fri, 18 Sep 2026 12:00:00 GMT"), 0.001,
                      "exactly now",)
      assert_in_delta(0.0, delay("X-RateLimit-Reset" => (NOW.to_i - 100).to_s))
      assert_in_delta(0.0, delay("X-RateLimit-Reset" => NOW.to_i.to_s))
    end

    test "RETRY-15 / RECOV-24: retry-after-ms and x-ms-retry-after-ms as integer milliseconds" do
      assert_in_delta(1.5, delay("retry-after-ms" => "1500"))
      assert_in_delta(0.25, delay("x-ms-retry-after-ms" => "250"))
      assert_in_delta(0.0, delay("retry-after-ms" => "0"))
      assert_nil(delay("retry-after-ms" => "1.5"), "milliseconds are an integer count")
    end

    test "RETRY-15 / RECOV-25: X-RateLimit-Reset as epoch seconds, jittered up to [100%, 120%]" do
      random = ::Random.new(20_260_918)
      pairs = { "X-RateLimit-Reset" => (NOW.to_i + 10).to_s }
      samples = Array.new(500) { delay_with(pairs, random) }

      samples.each do |d|
        assert_operator(d, :>=, 10.0)
        assert_operator(d, :<=, 12.0)
      end
      assert_operator(samples.uniq.size, :>, 100, "a real draw")
      assert_operator(samples.min, :<, 10.5)
      assert_operator(samples.max, :>, 11.5)
    end

    test "RETRY-21 / RECOV-24: the precedence returns the first parseable value" do
      assert_in_delta(5.0, delay("Retry-After" => "5", "retry-after-ms" => "9999"))
      assert_in_delta(1.0, delay("retry-after-ms" => "1000", "x-ms-retry-after-ms" => "9999"))
      assert_in_delta(2.0, delay("x-ms-retry-after-ms" => "2000",
                                 "X-RateLimit-Reset" => (NOW.to_i + 9_999).to_s,),)
    end

    test "RETRY-21: the stage stack's caller-configurable order is honoured as given" do
      pairs = { "Retry-After" => "5", "retry-after-ms" => "1000" }

      reversed = %w[retry-after-ms Retry-After]

      assert_in_delta(1.0, Policy.pacing_delay(headers(pairs), now: NOW, header_order: reversed))
      assert_nil(Policy.pacing_delay(headers(pairs), now: NOW, header_order: []))
      assert_nil(Policy.pacing_delay(headers(pairs), now: NOW, header_order: %w[X-RateLimit-Reset]))
    end

    test "HTTP-13: header names in the order are matched case-insensitively, through Headers#[]" do
      lower = headers("retry-after" => "5")

      assert_in_delta(5.0, Policy.pacing_delay(lower, now: NOW, header_order: %w[RETRY-AFTER]))
    end

    test "a multi-valued header is read by its first value" do
      builder = Dexpace::Headers.inbound_builder
      builder.add("Retry-After", "3")
      builder.add("Retry-After", "9")

      assert_in_delta(3.0, Policy.pacing_delay(builder.build, header_order: ORDER, now: NOW))
    end
  end

  # RETRY-16, RETRY-18, RETRY-19, RETRY-22, RECOV-23, RECOV-26, RECOV-29: the negative suite.
  class PacingTotalityTest < DexpaceTestCase
    include Fixtures

    ORDER = Policy::DEFAULT_PACING_HEADER_ORDER
    NOW = ::Time.utc(2026, 9, 18, 12, 0, 0)

    # No keyword parameter here on purpose: a braceless `delay("Retry-After" => "5")` would
    # otherwise be read as keywords under Ruby 3's separation.
    def delay(pairs)
      Policy.pacing_delay(headers(pairs), header_order: ORDER, now: NOW)
    end

    def delay_with(pairs, random)
      Policy.pacing_delay(headers(pairs), header_order: ORDER, now: NOW, random: random)
    end

    test "RETRY-19 / RECOV-24: the decimal screen rejects every non-decimal spelling first" do
      %w[0x10 1e3 5_0 5f 5d 30d 5s Infinity NaN 5,0 +5 .5 5. 0b1 1r 1i].each do |bad|
        assert_nil(delay("Retry-After" => bad), "expected #{bad.inspect} to be no hint")
      end
      assert_equal(50, Integer("5_0", 10), "the screen is load-bearing: Integer() reads this as 50")
    end

    test "RETRY-16 / RECOV-23: malformed, negative and out-of-range values are no hint, not 0" do
      ["-5", "-0.5", "not a date", "", " 5", "5 ", "Sun, 32 Nov 1994 08:49:37 GMT",
       "Sunday, 06-Nov-94 08:49:37 GMT", "9" * 16, "9" * 300, "9" * 400,].each do |bad|
        assert_nil(delay("Retry-After" => bad), bad.inspect)
      end
      ["-1", "1.5", "abc", "", "9" * 16, "9" * 400].each do |bad|
        assert_nil(delay("X-RateLimit-Reset" => bad), bad.inspect)
        assert_nil(delay("retry-after-ms" => bad), bad.inspect)
      end
    end

    test "RETRY-16: no matching header at all is no hint" do
      assert_nil(delay({}))
      assert_nil(delay("Content-Type" => "text/plain"))
    end

    test "RETRY-18 / RECOV-26: a finite computed delta past 365 days is clamped to the ceiling" do
      ceiling = Policy::MAX_PACING_DELAY_SECONDS.to_f

      assert_equal(ceiling, delay("Retry-After" => (400 * 24 * 60 * 60).to_s))
      assert_equal(ceiling, delay("retry-after-ms" => (400 * 24 * 60 * 60 * 1000).to_s))
      assert_equal(ceiling, delay("X-RateLimit-Reset" => (NOW.to_i + (400 * 24 * 60 * 60)).to_s))
      assert_equal(ceiling, delay("Retry-After" => "Fri, 18 Sep 2099 12:00:00 GMT"))
      assert_equal(ceiling, delay("Retry-After" => "9" * 15), "the longest run the grammar admits")
      assert_equal(ceiling, delay("retry-after-ms" => "9" * 15))
      assert_equal(ceiling, delay("X-RateLimit-Reset" => "9" * 15))
    end

    test "RETRY-18: exactly the ceiling and one below pass through unclamped" do
      ceiling = Policy::MAX_PACING_DELAY_SECONDS

      assert_equal(ceiling.to_f, delay("Retry-After" => ceiling.to_s))
      assert_equal(ceiling - 1.0, delay("Retry-After" => (ceiling - 1).to_s))
    end

    test "RETRY-22 / RECOV-29: one malformed header does not mask a later, well-formed one" do
      assert_in_delta(1.0, delay("Retry-After" => "garbage", "retry-after-ms" => "1000"))
      assert_in_delta(7.0, delay("Retry-After" => "30d", "retry-after-ms" => "x",
                                 "x-ms-retry-after-ms" => "7000",),)
    end

    test "RETRY-16: a parser that raises inside the dispatch is contained; the scan continues" do
      exploding = ::Object.new
      def exploding.rand(_range) = raise("generator down")
      pairs = { "X-RateLimit-Reset" => (NOW.to_i + 10).to_s, "Retry-After" => "garbage" }

      assert_nil(delay_with(pairs, exploding))
      assert_in_delta(2.0, delay_with(pairs.merge("retry-after-ms" => "2000"), exploding))
    end

    test "RETRY-19 / RECOV-24: the grammars are anchored, frozen, and carry their own timeout" do
      parsers = Dexpace::Resilience.const_get(:PacingParsers)
      %i[DECIMAL_GRAMMAR INTEGER_GRAMMAR].each do |name|
        grammar = parsers.const_get(name)

        assert_kind_of(::Regexp, grammar)
        refute_nil(grammar.timeout, "#{name}: per-pattern, never Regexp.timeout")
        assert_predicate(grammar, :frozen?)
        assert_match(/\A\\A.*\\z\z/, grammar.source, "#{name} is anchored at both ends")
      end
      refute_includes(Dexpace::Resilience.constants, :PacingParsers, "a private_constant")
    end

    test "RETRY-16: a value with no grammar at all -- a non-String -- is no hint" do
      forged = ::Object.new
      def forged.[](_name) = [nil]
      forged2 = ::Object.new
      def forged2.[](_name) = [42]

      assert_nil(Policy.pacing_delay(forged, header_order: ORDER, now: NOW))
      assert_nil(Policy.pacing_delay(forged2, header_order: ORDER, now: NOW))
    end
  end

  # RETRY-16, RETRY-19, NFR-6, P6-61: the parser's bounds -- a run past fifteen digits or a
  # value past 64 bytes is no hint before any conversion, so a hostile value costs microseconds
  # and emits no warning.
  class PacingBoundsTest < DexpaceTestCase
    include Fixtures

    ORDER = Policy::DEFAULT_PACING_HEADER_ORDER
    NOW = ::Time.utc(2026, 9, 18, 12, 0, 0)
    FORMS = %w[Retry-After retry-after-ms X-RateLimit-Reset].freeze

    def delay(pairs)
      Policy.pacing_delay(headers(pairs), header_order: ORDER, now: NOW)
    end

    # A headers stand-in answering one huge value: phase 1's inbound builder validates a value
    # byte by byte (seconds for 10 MB) and is not what is under test here; the parser is.
    def forged(name, value)
      stand_in = ::Object.new
      stand_in.define_singleton_method(:[]) { |asked| asked == name ? [value] : nil }
      stand_in
    end

    test "P6-61: a 10 MB value in every form is no hint, in microseconds, on the parser alone" do
      # The digit run exercises the grammars' bound in every form; the letter run exercises the
      # byte ceiling in front of the HTTP-date attempt, which 5a's anchored grammar would
      # otherwise scan (measured at 0.1 s for 10 MB). Both answer in well under a millisecond.
      cases = FORMS.map { |name| [name, "9" * 10_000_000] } << ["Retry-After", "x" * 10_000_000]
      cases.each do |name, huge|
        started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        answer = Policy.pacing_delay(forged(name, huge), header_order: [name], now: NOW)
        elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started

        assert_nil(answer, name)
        assert_operator(elapsed, :<, 0.05, "#{name} #{huge[0]}: #{elapsed} s; the value was read")
      end
    end

    test "NFR-6 / RETRY-16: a run long enough to overflow a Float emits no Ruby warning" do
      # The suite's raiser turns a warning into an error that Policy#parse_form's fence would
      # swallow, so the totality cases above cannot see one; recording the warnings can.
      FORMS.each do |name|
        warnings = WarningCapture.record { assert_nil(delay(name => "9" * 400), name) }

        assert_empty(warnings, "#{name}: String#to_f/#to_i ran on the run")
      end
    end

    test "P6-61: fifteen digits is the boundary, and the fraction is bounded the same way" do
      assert_equal(Policy::MAX_PACING_DELAY_SECONDS.to_f, delay("Retry-After" => "1" * 15))
      assert_nil(delay("Retry-After" => "1" * 16))
      assert_in_delta(1.5, delay("Retry-After" => "1.5"))
      assert_in_delta("1.#{"5" * 15}".to_f, delay("Retry-After" => "1.#{"5" * 15}"), 0.0)
      assert_nil(delay("Retry-After" => "1.#{"5" * 16}"))
      assert_in_delta(1.5, delay("retry-after-ms" => "1500"))
      assert_nil(delay("retry-after-ms" => "1500.0"), "millis take no fraction")
    end

    test "P6-61: the 64-byte ceiling sits above every well-formed form" do
      parsers = Dexpace::Resilience.const_get(:PacingParsers)

      assert_equal(64, parsers.const_get(:MAX_VALUE_BYTES))
      # The two longest well-formed values -- the 29-byte RFC 1123 date and the 31-byte decimal
      # the bounded grammar admits (fifteen digits, a point, fifteen digits) -- both parse.
      longest = "#{"1" * 15}.#{"5" * 15}"

      assert_equal(31, longest.bytesize)
      assert_in_delta(45.0, delay("Retry-After" => "Fri, 18 Sep 2026 12:00:45 GMT"))
      assert_equal(Policy::MAX_PACING_DELAY_SECONDS.to_f, delay("Retry-After" => longest))
      assert_nil(delay("Retry-After" => "x" * 65))
      assert_nil(delay("Retry-After" => "x" * 64), "the date grammar refuses; the ceiling admits")
    end
  end
end
