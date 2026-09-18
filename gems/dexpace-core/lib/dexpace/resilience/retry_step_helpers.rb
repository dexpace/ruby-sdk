# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "policy"
require_relative "resend"
require_relative "retry_settings"
require_relative "../error/protocol_error"
require_relative "../error/retry_predicate_error"
require_relative "../error/invalid_argument_error"
require_relative "../instrumentation/contain"
require_relative "../instrumentation/keys"
require_relative "../instrumentation/logger"
require_relative "../instrumentation/http_tracer"
require_relative "../pipeline/stages"

module Dexpace
  module Resilience
    # What RetryStep and AsyncRetryStep share above Policy itself: the constructor's validation,
    # the retry DECISION (both axes, the caller's predicate, the budget) and the delay
    # RESOLUTION (RETRY-39's precedence with RETRY-40's fatal/non-fatal split), so RETRY-13's
    # "one calculator" extends to the logic sitting on it and the two drivers cannot drift
    # (design §11.12's rule for every sync/async pair). A private_constant mixin with a sig/
    # mirror -- the strict `core` target types its two includers -- and no test/ mirror: every
    # branch is asserted through the two steps (P6-11, as built).
    #
    # RETRY-28 in the source: no method here names RetrySettings#total_timeout or
    # Policy.budget_remaining, and neither driver does either -- the text scan in
    # retry_step_test.rb is the guard.
    module RetryStepHelpers
      # The three answers a decision can give. Only :exhausted emits retries_exhausted: a failure
      # that was never retryable is not an exhausted retry (5c's ordering test, third case).
      RETRY = :retry
      EXHAUSTED = :exhausted
      STOP = :stop
      private_constant :RETRY, :EXHAUSTED, :STOP

      private

      # The constructor's validation, shared: the settings are a RetrySettings, the factory and
      # the two hooks are callables, the logger is a Logger.
      def initialize_retry_step(settings:, http_tracer_factory:, delay_override:, should_retry:,
                                logger:)
        unless settings.is_a?(RetrySettings)
          raise InvalidArgumentError, "settings: takes a RetrySettings, got #{settings.class}"
        end
        unless logger.is_a?(Instrumentation::Logger)
          raise InvalidArgumentError, "logger: takes an Instrumentation::Logger, got " \
                                      "#{logger.class}"
        end

        @settings = settings
        @http_tracer_factory = callable!("http_tracer_factory", http_tracer_factory)
        @delay_override = delay_override.nil? ? nil : callable!("delay_override", delay_override)
        @should_retry = should_retry.nil? ? nil : callable!("should_retry", should_retry)
        @logger = logger
      end

      def callable!(name, value)
        return value if value.respond_to?(:call)

        raise InvalidArgumentError, "#{name}: must answer #call"
      end

      # RETRY-41 at the top of every call: the per-call override wins over the configured value.
      def effective_max_retries(cursor)
        Policy.effective_max_retries(override: cursor.options.max_retries,
                                     configured: @settings.max_retries, logger: @logger,)
      end

      # RETRY-23 first: a cancellation -- the token's own raise or one a downstream wrapped --
      # is terminal before any axis is consulted, so a caller's should_retry never sees it and
      # can never answer true for it (P6-60). Then RETRY-8's BOTH axes, neither implying the
      # other, in this order -- re-sendability first and unconditionally (a caller predicate may
      # widen or narrow the CONDITION and may never authorise re-sending a bare POST or a consumed
      # body, RETRY-7), then the condition (Policy.retryable? or the caller's predicate,
      # RETRY-39/RETRY-40), then the budget. The budget comes LAST so that :exhausted means
      # exactly "retryable, and the budget is spent".
      #
      # @return [Symbol] RETRY, EXHAUSTED or STOP
      def decision(request, failure, attempt, max_retries)
        return STOP if Policy.cancellation?(failure)
        return STOP unless Resend.eligible?(request)
        return STOP unless retryable_condition?(failure, request)

        attempt <= max_retries ? RETRY : EXHAUSTED
      end

      # The condition axis: the shared classifier by default, the caller's predicate when one
      # was supplied -- and a predicate that raises a StandardError aborts the call as
      # RetryPredicateError with the raise as its cause (RETRY-40). The fatal family passes
      # through the absent arm unchanged (RETRY-25).
      def retryable_condition?(failure, request)
        if @should_retry.nil?
          return Policy.retryable?(failure, retryable_statuses: @settings.retryable_statuses)
        end

        begin
          @should_retry.call(failure, request) ? true : false
        rescue ::StandardError => error
          raise RetryPredicateError.new("the should_retry predicate raised #{error.class}"),
                cause: error
        end
      end

      # RETRY-39: caller delay-override, then the server's pacing headers on the response path
      # only, then exponential backoff. (The fixed-delay tier between the last two is RETRY-43,
      # a MAY declined for v1, so the precedence has three live sources.) `now:` is the settings
      # clock's, so a fake clock drives the absolute forms.
      def resolve_delay(attempt, response, failure)
        overridden = overridden_delay(attempt, response, failure)
        return overridden unless overridden.nil?

        if response
          hinted = Policy.pacing_delay(response.headers, header_order: @settings.header_order,
                                                         now: @settings.clock.now,
                                                         random: @settings.random,)
          return hinted unless hinted.nil?
        end

        Policy.backoff_delay(attempt, **@settings.backoff_arguments)
      end

      # RETRY-40's non-fatal half: a delay-override that raises a StandardError, or answers
      # something that is not a non-negative number, is logged as one WARNING diagnostic through
      # 5b's facade (contained, OBS-20) and the precedence falls through. nil is the documented
      # "no opinion" answer and is not logged. The fatal family propagates (RETRY-25).
      def overridden_delay(attempt, response, failure)
        return nil if @delay_override.nil?

        value = @delay_override.call(attempt, response, failure)
        return nil if value.nil?
        return Float(value) if value.is_a?(::Numeric) && value.finite? && !value.negative?

        report_override(message: "delay_override answered #{value.inspect}; falling back " \
                                 "(RETRY-40)")
        nil
      rescue ::StandardError => error
        report_override(cause: error, message: "delay_override raised; falling back (RETRY-40)")
        nil
      end

      def report_override(message:, cause: nil)
        Instrumentation.diagnostic(@logger, event: Instrumentation::Events::INSTRUMENTATION_HOOK,
                                            cause: cause, message: message,)
      end

      # The Exception the tracer and the trail carry for an attempt: the throwable itself, or
      # the error-status response converted ONCE, so the object the tracer reported is the object
      # the trail holds (OBS-28: #attempt_failed's second argument is an Exception).
      def failure_of(response, error)
        return error unless error.nil?
        raise InvalidArgumentError, "an attempt yields a response or an error" if response.nil?

        ProtocolError.for(response)
      end

      # RETRY-34's terminal attachment: every prior attempt's failure onto the surfaced instance,
      # through the one helper whose skip-self guard is 4b's.
      def attach_trail(error, trail)
        trail.each { |prior| Dexpace.attach_suppressed(error, prior) }
        error
      end
    end
    private_constant :RetryStepHelpers
  end
end
