# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../each_cause"
require_relative "../error/cancelled_error"
require_relative "../error/invalid_argument_error"
require_relative "../error/protocol_error"
require_relative "../instrumentation/contain"
require_relative "../instrumentation/keys"
require_relative "../instrumentation/logger"
require_relative "pacing_parsers"

module Dexpace
  # The resilience layer: phase 6's namespace, design §6.1's. Retry is 6a's; redirect (6b) and
  # authentication (6c) add their own constants beside these.
  module Resilience
    # The ONE shared retry policy core (RETRY-13, RECOV-30): the tuning constants, the backoff
    # calculator, the pacing-header dispatcher, the two-branch retryability consult and the
    # effective-retry-count resolver. Both retry stacks -- RecoveryRetry beneath phase 4b's
    # orchestrator and RetryStep/AsyncRetryStep at Stages::RETRY -- call these exact methods and
    # carry no formula or constant of their own; a text scan over lib/dexpace/resilience/ for a
    # literal delay constant outside this file is the mechanised form of that claim.
    #
    # A module with no instance side, frozen constants and pure functions, so RETRY-42's
    # "immutable and stateless after construction and safe for concurrent invocation" is
    # structural: nothing here has state to share. `extend self` and never module_function
    # (Style/ModuleFunction), on 5a's HTTPDate and Retryability precedent.
    #
    # Public (R5): a generated SDK assembling its own retry driver needs to call the SAME
    # calculator, and XCUT-6's capability query is the extension point a third-party transport
    # uses by defining #retryable? on its own error class -- both only work if the consulting
    # code is public and stable. It coexists with 5a's Dexpace::Retryability without touching
    # it: that module is XCUT-5's fixed baked classifier, read once by ProtocolError at
    # construction; .retry_eligible? below is XCUT-7's CONFIGURABLE set, consulted by the retry
    # drivers, and neither reads the other (XCUT-5's closing NOTE, P6-10).
    #
    # Two budget policies, one calculator (R6, P6-5): .backoff_delay takes no total-timeout
    # parameter at all, and RECOV-20's budget is the separate .budget_remaining that only
    # RecoveryRetry calls. RETRY-28's prohibition on the stage stack is then a fact about which
    # files name which method, checkable by a text scan, rather than a keyword every future edit
    # must remember not to pass.
    module Policy
      extend self

      # RETRY-12's first default: the wait before the first retry, 200 ms in seconds. The five
      # defaults are one schedule -- 200 ms, x2, 8 s, 0.2 and three sends -- and every one is
      # read from here by RetrySettings and re-typed nowhere (RETRY-13).
      DEFAULT_INITIAL_DELAY = 0.2
      # RETRY-12: the exponential factor between successive waits.
      DEFAULT_MULTIPLIER = 2.0
      # RETRY-12: the cap on any one wait, 8 s in seconds.
      DEFAULT_MAX_DELAY = 8.0
      # RETRY-12: the symmetric jitter fraction, a fifth of the delay either way.
      DEFAULT_JITTER = 0.2
      # RETRY-12's budget of three sends, spelled in the STAGE vocabulary as two retries after
      # the initial send; the recovery stack's max-attempts is this plus one (RETRY-14, P6-6).
      DEFAULT_MAX_RETRIES = 2

      # XCUT-7's configurable retryable-status set, at its default: a SUBSET of Retryability's
      # baked classification (which also admits 500-599 less 501 and 505 in full), enumerable
      # because it is data and not a rule.
      DEFAULT_RETRYABLE_STATUSES = ::Set[408, 429, 500, 502, 503, 504].freeze

      # RETRY-21's fixed recovery-stack precedence, and the stage stack's default when a caller
      # configures no order of its own: Retry-After (numeric, then date), the two millisecond
      # variants, then the epoch reset.
      DEFAULT_PACING_HEADER_ORDER = %w[
        Retry-After retry-after-ms x-ms-retry-after-ms X-RateLimit-Reset
      ].freeze

      # RETRY-18 / RECOV-26: the finite ceiling every pacing delta is clamped to, 365 days in
      # seconds, applied before any nanosecond conversion could overflow.
      MAX_PACING_DELAY_SECONDS = 365 * 24 * 60 * 60

      # RECOV-34's representability ceiling: the largest signed 64-bit nanosecond count, ~292
      # years, which design §10.18 substitutes for the reference's Duration bound.
      MAX_DURATION_NANOSECONDS = (1 << 63) - 1

      # Sub-nanosecond: RETRY-10's degenerate jitter range, below which the base delay is
      # returned unperturbed.
      NANOSECOND = 1e-9
      private_constant :NANOSECOND

      # RETRY-37 / XCUT-7 / RECOV-17: whether `status` is in the CONFIGURED retryable-status
      # set, consulted alone -- authoritative-contains, never AND-ed with XCUT-5's baked flag.
      # There is no baked-flag parameter on this method by design, so the intersection RETRY-37
      # forbids is a method that does not exist. A set that NARROWS narrows: 500 is retryable
      # under Retryability and refused here when the set omits it.
      #
      # @param status [Integer] the response status code
      # @param set [Set<Integer>] the configured retryable-status set
      # @return [Boolean]
      def retry_eligible?(status, set:)
        set.include?(status)
      end

      # RETRY-2 / XCUT-6 / CFG-35's throwable half: the retryable-throwable set, defined here and
      # nowhere else, as the CAPABILITY query -- `respond_to?(:retryable?) && retryable?` --
      # walked over the error and its whole cause chain through Dexpace.each_cause, which is
      # already cycle-safe by reference identity (XCUT-9), so RETRY-2's termination clause needs
      # no second walk. Never a concrete-type match: `is_a?(::IOError)` is wrong in both
      # directions (5a's R1) -- it would call phase 3a's StreamError retryable and a bare
      # Errno::ETIMEDOUT not. The residual that comes with the capability form is P6-4: a bare,
      # unwrapped stdlib I/O or timeout error answers no capability and classifies not
      # retryable, which is why phase 8's adapters must wrap what they let escape.
      #
      # @param error [Exception]
      # @return [Boolean]
      def throwable_retryable?(error)
        Dexpace.each_cause(error).any? do |cause|
          # The capability is a duck type the signature cannot name; probed untyped, as 5a's
          # Retryability probes #code.
          probe = cause #: untyped
          probe.respond_to?(:retryable?) && probe.retryable?
        end
      end

      # RETRY-23 / RECOV-27: whether `error` is a cancellation -- a Dexpace::CancelledError
      # itself, or one anywhere in its cause chain, so a transport that wrapped the token's raise
      # in an error of its own (one that may well answer #retryable?) is still read as the
      # cancellation it carries. Consulted BEFORE either branch of .retryable? and before a
      # caller's should_retry predicate on the stage drivers, so "cancellation MUST never be
      # treated as a retryable failure" holds whatever a capability or a predicate answers
      # (P6-60). The walk is Dexpace.each_cause, cycle-safe by identity (XCUT-9).
      #
      # @param error [Exception]
      # @return [Boolean]
      def cancellation?(error)
        Dexpace.each_cause(error).any?(Dexpace::CancelledError)
      end

      # The one dispatch point both stacks call: a cancellation is never retryable (RETRY-23),
      # then a ProtocolError is classified by its status against the configured set (RETRY-37),
      # anything else by the capability query (RETRY-2). A ProtocolError deliberately does not
      # answer #retryable? (P6-10), so a wrapped one buried in a cause chain can never smuggle
      # the baked set past the configured one.
      #
      # @param error [Exception]
      # @param retryable_statuses [Set<Integer>] the configured set
      # @return [Boolean]
      def retryable?(error, retryable_statuses:)
        return false if cancellation?(error)

        if error.is_a?(Dexpace::ProtocolError)
          retry_eligible?(error.status.code, set: retryable_statuses)
        else
          throwable_retryable?(error)
        end
      end

      # RETRY-9, RETRY-10, RETRY-11, RECOV-21: `initial_delay * multiplier**(attempt - 1)`,
      # capped at `max_delay`, then symmetric jitter drawn uniformly from
      # [d * (1 - j/2), d * (1 + j/2)] -- midpoint d, j = 0 returning d exactly, a degenerate
      # sub-nanosecond spread returning d, a negative sample floored to zero. `attempt` is
      # 1-based, 1 being the wait before the first retry, and anything below is refused.
      #
      # Overflow-safe by Ruby's own float arithmetic plus ONE guard: `2.0**9999` is Infinity
      # (never a raise, verified on 3.2.11, 3.4.10 and 4.0.6) and `[Infinity, max_delay].min` is
      # `max_delay`, so a large attempt saturates to the cap -- but `0.0 * Infinity` is NaN, and
      # `[NaN, 8.0].min` RAISES ("comparison of Float with NaN failed"), so a zero initial delay
      # answers zero without touching the power (found by the 2000-attempt trampoline test;
      # P6-53). No budget parameter: the total-timeout is RecoveryRetry's alone, applied through
      # .budget_remaining (R6).
      #
      # @param attempt [Integer] 1-based
      # @param initial_delay [Float] seconds
      # @param multiplier [Float] >= 1.0
      # @param max_delay [Float] seconds, the cap
      # @param jitter [Float] in [0.0, 1.0]
      # @param random [#rand] the generator the jitter sample is drawn from
      # @return [Float] seconds
      # @raise [Dexpace::InvalidArgumentError] for an attempt below 1
      def backoff_delay(attempt, initial_delay:, multiplier:, max_delay:, jitter:, random:)
        unless attempt.is_a?(::Integer) && attempt >= 1
          raise InvalidArgumentError, "attempt must be an Integer >= 1, got #{attempt.inspect}"
        end

        initial = seconds(initial_delay)
        return 0.0 if initial.zero?

        raw = initial * (seconds(multiplier)**(attempt - 1))
        jittered([raw, seconds(max_delay)].min, jitter, random)
      end

      # RETRY-15 through RETRY-22, RECOV-22 through RECOV-26, RECOV-29: the total pacing
      # dispatch. Walks `header_order` -- the recovery stack's fixed precedence or the stage
      # stack's caller-configurable list (RETRY-21) -- and returns the first usable value,
      # clamped to MAX_PACING_DELAY_SECONDS, or nil for no hint. Each form's parser is total and
      # every parser call is fenced besides, so a malformed value in one header falls through to
      # the next rather than aborting the scan, and nothing here ever raises: RETRY-22's "a
      # failure while parsing a pacing header MUST NOT mask the real upstream failure" is honoured
      # one level up, by the caller falling back to .backoff_delay on nil, and one level down,
      # by no single value poisoning the scan. A result that is not finite is no hint (RETRY-16's
      # out-of-range clause); a finite one past the ceiling is the ceiling (RETRY-18).
      #
      # @param headers [Dexpace::Headers] the response's headers
      # @param header_order [Array<String>] the names to consult, in precedence order
      # @param now [Time] the instant absolute forms are measured from; the driver passes its
      #   clock's so a fake clock drives the arithmetic
      # @param random [#rand] the generator RECOV-25's reset jitter draws from
      # @return [Float, nil] seconds, or nil for no hint
      def pacing_delay(headers, header_order:, now: ::Time.now, random: ::Random)
        header_order.each do |name|
          value = headers[name]&.first
          next if value.nil?

          delay = parse_form(name, value, now, random)
          next unless delay.is_a?(::Float) && delay.finite? && delay >= 0.0

          return [delay, MAX_PACING_DELAY_SECONDS.to_f].min
        end
        nil
      end

      # RETRY-41: the stage stack's effective retry count -- a present per-call override wins
      # (validated non-negative), else the configured value, with a negative configured value
      # clamped to DEFAULT_MAX_RETRIES and the clamp logged; zero means no retries. The log is a
      # WARNING `http.instrumentation.config` diagnostic through 5b's facade, contained (OBS-20)
      # so a raising sink cannot fail the request, and Logger::NULL by default so the
      # non-clamping path allocates nothing and touches no sink (P6-12).
      #
      # @param override [Integer, nil] the per-call RequestOptions#max_retries
      # @param configured [Integer] the settings' max_retries
      # @param logger [Dexpace::Instrumentation::Logger] where the clamp is reported
      # @return [Integer] >= 0
      # @raise [Dexpace::InvalidArgumentError] for a negative override
      def effective_max_retries(override:, configured:, logger: Instrumentation::Logger::NULL)
        unless override.nil?
          unless override.is_a?(::Integer) && override >= 0
            raise InvalidArgumentError, "max_retries override must be a non-negative Integer"
          end

          return override
        end
        return configured if configured >= 0

        Instrumentation.diagnostic(
          logger, event: Instrumentation::Events::INSTRUMENTATION_CONFIG,
                  message: "max_retries #{configured} is negative and was clamped to " \
                           "#{DEFAULT_MAX_RETRIES} (RETRY-41)",
        )
        DEFAULT_MAX_RETRIES
      end

      # RECOV-20 / RETRY-27: the recovery stack's budget, as the time REMAINING -- never the
      # elapsed figure -- so every caller compares one number against a delay: Float::INFINITY
      # when the budget is zero ("unbounded, deadline disabled"), else `total_timeout - elapsed`,
      # which is negative once the budget is spent. Recovery-driver only: RetryStep and
      # AsyncRetryStep never call this, which is what makes RETRY-28 a property of the source
      # (R6, P6-5).
      #
      # @param elapsed [Float] seconds since the engine's own start instant
      # @param total_timeout [Numeric] seconds; zero disables the budget
      # @return [Float] seconds remaining, possibly negative, or Float::INFINITY
      def budget_remaining(elapsed:, total_timeout:)
        return ::Float::INFINITY if total_timeout.zero?

        seconds(total_timeout) - seconds(elapsed)
      end

      private

      # A Numeric as a Float. rbs's Numeric declares no #to_f (its subclasses do), and Kernel#Float
      # is typed as answering nil, so the conversion reads the value untyped -- the same spelling
      # 5a's Clock::Guard uses.
      def seconds(value)
        number = value #: untyped
        number.to_f
      end

      # RETRY-10's symmetric draw over [d(1 - j/2), d(1 + j/2)]: d itself for j = 0 or a
      # sub-nanosecond spread, and a negative sample floored at zero.
      def jittered(unjittered, jitter, random)
        return unjittered if jitter.zero?

        spread = unjittered * jitter
        return unjittered if spread < NANOSECOND

        half = spread / 2.0
        [random.rand((unjittered - half)..(unjittered + half)), 0.0].max
      end

      # The per-form dispatch, fenced: a parser is total by contract and this rescue is the
      # belt behind it. Header names are matched case-insensitively with a bare #downcase
      # (HTTP-13); Headers#[] already folded the lookup.
      def parse_form(name, value, now, random)
        case name.downcase
        when "retry-after" then PacingParsers.parse_retry_after(value, now: now)
        when "retry-after-ms", "x-ms-retry-after-ms" then PacingParsers.parse_millis(value)
        when "x-ratelimit-reset"
          PacingParsers.parse_epoch_reset(value, now: now, random: random)
        end
      rescue ::StandardError
        nil
      end
    end
  end
end
