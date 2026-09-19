# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "policy"
require_relative "resend"
require_relative "retry_settings"
require_relative "../recovery"
require_relative "../registry"
require_relative "../error/protocol_error"
require_relative "../error/cancelled_error"
require_relative "../error/invalid_argument_error"
require_relative "../instrumentation/http_tracer"
require_relative "../instrumentation/logger"

module Dexpace
  module Resilience
    # The recovery-chain retry: chapter 9's FIRST stack, RECOV-17 through RECOV-30 and RECOV-34,
    # which phase 4 postponed here. Installed as Recovery::Orchestrator's own `transport:`
    # argument, decorating the raw transport, and NOT as a Recovery::ResponseChain recovery
    # step (P6-3): Recovery::Transform#apply(outcome) carries no request to re-send, while
    # RECOV-19's "each RE-SENT attempt's response MUST be re-classified" describes an engine
    # that dispatches its own re-sends and inspects each -- which only a transport-decorator
    # position can do while keeping RequestChain's stamping (the idempotency key, the client
    # identity) applied exactly once per exchange rather than once per attempt. It is itself a
    # Dexpace::Transport by phase 2's duck type, so it composes anywhere a transport does.
    #
    # Sitting BELOW the orchestrator's rescue region, a transport that raises reaches this
    # engine as an exception (P6-8), so a connection reset or a socket timeout -- RECOV-17's and
    # RETRY-4's "always retryable" case -- is retried here rather than converted first and
    # never retried; only StandardError is rescued and the fatal family propagates at the throw
    # site (RETRY-25). Each attempt's response is classified through phase 4b's own two
    # primitives, Recovery.buffer_error_body then ProtocolError.for_or_nil, purely to decide
    # whether to keep going (RECOV-19, RETRY-36): the buffering is what releases the connection
    # before the wait (RETRY-35, RECOV-16), and the BUFFERED response is what every later line
    # sees -- the pacing parse, the RECOV-19 pass-through, and whatever ErrorMappingStep the
    # caller configured, which runs exactly once, on the terminal response, with the caller's
    # own factory (the plan's open question 4: this engine has no factory: keyword).
    #
    # Two terminal shapes (P6-9): a RESPONSE whose failure was never retryable -- a status
    # outside the configured set, or a request that was not re-sendable -- is RETURNED, "passes
    # through as Success" (RECOV-19), for the outer chain to map; a THROWABLE is raised whether
    # it was retryable or not, and so is a retryable status that met a spent attempt cap or a
    # spent total-timeout -- "the terminal failure's throwable MUST be surfaced" (RECOV-20) --
    # with every prior attempt's failure attached as suppressed first (RETRY-34) and, when the
    # budget is what stopped a retryable failure, retries_exhausted emitted immediately before.
    #
    # The budget (RECOV-20, RETRY-27): a maximum-attempts cap that counts the initial send as
    # attempt 1 -- RetrySettings#max_retries plus one, an identity and never a second number
    # (RETRY-14, P6-6) -- AND a total-timeout applied as the time REMAINING through
    # Policy.budget_remaining, zero meaning unbounded; a delay that would push the elapsed time
    # past the budget is suppressed and the last failure surfaced, so no wait can overshoot
    # (RECOV-21's clamp, RECOV-22's on a hint). The elapsed figure is the settings clock's
    # monotonic reading, never Time.now (CFG-16). The wait is Clock#sleep with the caller's
    # token (RECOV-27, CFG-15), the token is checked at every attempt boundary too, and a
    # cancellation surfaces as the CancelledError it raised, which aborts the loop and is never
    # itself retryable (RETRY-23). RECOV-28: the attempt count, the start instant and the trail
    # are locals of one #call; nothing is written to this frozen object.
    #
    # OBS-29's per-attempt group goes through the tracer `http_tracer_factory:` produces once
    # per operation, called with the REQUEST -- there is no cursor on this stack -- which is
    # also the `context` every callback receives. retries_exhausted fires immediately before the
    # terminal raise and only there (a returned response was never retryable, and a spent
    # budget on a retryable failure is always a raise here); nothing emits operation_failed,
    # which docs/first-release.md's behavioural-asymmetries entry records as conforming.
    class RecoveryRetry
      private_class_method :new

      # Builds a frozen engine over `transport`.
      #
      # @param transport [#call] the raw Dexpace::Transport this engine decorates
      # @param settings [RetrySettings] the shared configuration; total_timeout is read here
      # @param http_tracer_factory [#call] called once per operation with the request; the
      #   frozen no-op NULL by default
      # @param logger [Instrumentation::Logger] where RETRY-41's clamp is reported, contained
      # @return [RecoveryRetry] frozen
      # @raise [Dexpace::InvalidArgumentError] for a transport that is not a three-positional
      #   callable, a settings that is not a RetrySettings, or a logger that is not a Logger
      def self.build(transport:, settings: RetrySettings.build,
                     http_tracer_factory: NULL_TRACER_FACTORY,
                     logger: Instrumentation::Logger::NULL)
        new(transport: transport, settings: settings, http_tracer_factory: http_tracer_factory,
            logger: logger,).freeze
      end

      NULL_TRACER_FACTORY = ->(_request) { Instrumentation::NULL }
      private_constant :NULL_TRACER_FACTORY

      def initialize(transport:, settings:, http_tracer_factory:, logger:)
        unless Registry.callable?(transport, arity: 3)
          raise InvalidArgumentError,
                "transport: must be a Dexpace::Transport, a callable of three positionals"
        end
        unless settings.is_a?(RetrySettings)
          raise InvalidArgumentError, "settings: takes a RetrySettings, got #{settings.class}"
        end
        unless http_tracer_factory.respond_to?(:call)
          raise InvalidArgumentError, "http_tracer_factory: must answer #call(request)"
        end
        unless logger.is_a?(Instrumentation::Logger)
          raise InvalidArgumentError, "logger: takes an Instrumentation::Logger"
        end

        @transport = transport
        @settings = settings
        @http_tracer_factory = http_tracer_factory
        @logger = logger
      end

      # The transport SPI: one exchange, retried within the budget.
      #
      # @param request [Dexpace::Request] re-sent as the same object on every attempt
      # @param options [Dexpace::RequestOptions] threaded to the transport unchanged
      # @param cancellation [Dexpace::Cancellation] the token the wait and every boundary honour
      # @return [Dexpace::Response] the terminal response -- a success, or an error status that
      #   was never retryable, buffered
      # @raise [Exception] the terminal throwable, carrying the prior trail as suppressed
      # @raise [Dexpace::CancelledError] when the token is cancelled
      def call(request, options, cancellation)
        run = Run.new(tracer: @http_tracer_factory.call(request), request: request,
                      options: options, cancellation: cancellation, max_attempts: max_attempts,
                      started: @settings.clock.monotonic, trail: [],)
        attempt = 1
        loop do
          terminal = attempt_once(run, attempt)
          return terminal unless terminal.nil?

          attempt += 1
        end
      end

      # The per-call locals (RECOV-28): on the stack, never on the engine.
      class Run < Data.define(:tracer, :request, :options, :cancellation, :max_attempts, :started,
                              :trail,)
      end
      private_constant :Run

      RETRY = :retry
      EXHAUSTED = :exhausted
      STOP = :stop
      private_constant :RETRY, :EXHAUSTED, :STOP

      private

      # One attempt: the boundary check, the tracer, the send, the decision, and -- on a retry
      # -- the budgeted delay and the wait. Answers the terminal response, or nil for "again".
      def attempt_once(run, attempt)
        run.cancellation.check!
        run.tracer.attempt_started(run.request, attempt)
        response, error = exchange(run.request, run.options, run.cancellation)
        return response if error.nil?

        verdict = decision(run.request, error, attempt, run.max_attempts)
        return response if verdict == STOP && response

        surface(run, error, exhausted: verdict == EXHAUSTED) unless verdict == RETRY
        wait(run, attempt, response, error)
      end

      # The retry path: the delay against the budget (nil surfaces the failure, RECOV-20), the
      # tracer, the trail, then the wait on the settings' clock with the caller's token.
      #
      # @return [nil] always: the loop's "again"
      def wait(run, attempt, response, error)
        delay = delay_within_budget(run, attempt, response)
        surface(run, error, exhausted: true) if delay.nil?
        run.tracer.attempt_failed(run.request, error, delay)
        run.trail << error
        @settings.clock.sleep(delay, cancellation: run.cancellation)
      end

      # RETRY-14 / P6-6: the attempts cap is the stage vocabulary plus the initial send, with
      # RETRY-41's clamp applied to the configured value on this stack too.
      def max_attempts
        Policy.effective_max_retries(override: nil, configured: @settings.max_retries,
                                     logger: @logger,) + 1
      end

      # One send, classified: a success or a non-error status is [response, nil]; an error
      # status is buffered (RECOV-16, the release before the wait) and paired with its
      # ProtocolError; a raise is [nil, error]. StandardError only (RETRY-25).
      def exchange(request, options, cancellation)
        response = @transport.call(request, options, cancellation)
        return [response, nil] unless response.status.error?

        buffered = Recovery.buffer_error_body(response)
        [buffered, ProtocolError.for(buffered)]
      rescue ::StandardError => error
        [nil, error]
      end

      # RECOV-17 and RECOV-18: the configured set for a status, the capability for a throwable
      # (Policy.retryable?), AND the re-sendability gate -- then the cap. :stop is "never
      # retryable", :exhausted "retryable, cap spent".
      def decision(request, error, attempt, max_attempts)
        return STOP unless Resend.eligible?(request)
        return STOP unless Policy.retryable?(error,
                                             retryable_statuses: @settings.retryable_statuses,)

        attempt < max_attempts ? RETRY : EXHAUSTED
      end

      # RECOV-20, RECOV-21, RECOV-22, RETRY-27: the delay -- the pacing hint from the buffered
      # response through the fixed precedence, else the shared backoff -- against the budget
      # REMAINING. nil when the budget is spent or the delay would overshoot it: RECOV-20's
      # "suppressed, and the last failure surfaced unchanged". A zero budget is unbounded.
      def delay_within_budget(run, attempt, response)
        delay = hinted_delay(response) || Policy.backoff_delay(attempt,
                                                               **@settings.backoff_arguments,)
        elapsed = @settings.clock.monotonic - run.started
        remaining = Policy.budget_remaining(elapsed: elapsed,
                                            total_timeout: @settings.total_timeout,)
        return nil if remaining <= 0.0 || delay > remaining

        delay
      end

      # RECOV-22 through RECOV-24, RECOV-29: the recovery stack's FIXED precedence, from the
      # still-open (buffered) response; nil when there is no response or no usable hint, which is
      # what makes a malformed header fall back to backoff without masking the failure.
      def hinted_delay(response)
        return nil if response.nil?

        Policy.pacing_delay(response.headers, header_order: Policy::DEFAULT_PACING_HEADER_ORDER,
                                              now: @settings.clock.now, random: @settings.random,)
      end

      # RECOV-20's surfacing and RETRY-34's trail: retries_exhausted when the budget stopped a
      # retryable failure (never for one that was never retryable), then the carried raise.
      def surface(run, error, exhausted:)
        run.trail.each { |prior| Dexpace.attach_suppressed(error, prior) }
        run.tracer.retries_exhausted(run.request, error) if exhausted
        raise error, cause: nil # pipeline/7ce4431d: a carried error, never a bare raise
      end
    end
  end
end
