# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "retry_step_helpers"
require_relative "../error/cancelled_error"
require_relative "../pipeline/stages"
require_relative "../instrumentation/http_tracer"
require_relative "../instrumentation/logger"

module Dexpace
  module Resilience
    # The stage-based retry step, synchronous half: chapter 9's second stack at Stages::RETRY
    # (order 500, between REDIRECT and AUTH, PIPE-2), driving the downstream chain once per
    # attempt through a FRESH fork of its cursor -- for every drive, the first included, and
    # never through its own cursor's #call (pipeline/86343352, P4-39) -- so hop 1 and hop n are
    # the same object and each attempt re-executes the chain with fresh per-attempt state
    # (RETRY-44). It writes no cursor state of its own (boundary 2: the cross-origin marker is
    # 6b's and 6c's), so a RETRY fork's slot stays empty under every stage's key.
    #
    # RETRY-42: constructed once, frozen, shared by every call a pipeline serves, and stateless
    # -- the attempt counter, the trail and the tracer are locals of one #call. The wait is 5a's
    # cancellable queue wait, Clock#sleep(duration, cancellation:) on the settings' clock, never
    # Kernel#sleep and never an interrupt (RETRY-26, CFG-15, boundary 5), and the cancellation
    # token is checked at the top of EVERY attempt as well as by the wait (RETRY-23, RECOV-27).
    # No total-timeout: nothing in this file or in RetryStepHelpers names
    # RetrySettings#total_timeout or Policy.budget_remaining, which is RETRY-28 as a property of
    # the source (R6, P6-5).
    #
    # OBS-29's per-attempt group is emitted through the tracer `http_tracer_factory:` produces
    # -- called ONCE per #call, with the cursor as its argument and as the `context` every
    # callback receives (R3, P6-7) -- and never through Cursor#bundle, whose tracer factory
    # produces span tracers (a different kind of object). attempt_started before every drive,
    # attempt_failed with the resolved delay before every wait, and retries_exhausted only when
    # a RETRYABLE failure met a spent budget; the operation-lifecycle triple is emitted by
    # nothing in v1 (docs/first-release.md's behavioural-asymmetries entry). A throwing tracer
    # propagates and fails the request: OBS-30 puts that on the implementer, and core wraps no
    # tracer callback in a rescue (OBS-20's carve-out).
    #
    # RETRY-35's three orderings, in #call: the delay is resolved from the still-open response
    # FIRST, the response is closed BEFORE the wait, and both the retry decision and the delay
    # resolution are fenced so the response is closed before any throwable -- a
    # RetryPredicateError above all -- propagates. RETRY-34 on the terminal path: the whole
    # prior trail is attached to the instance actually surfaced, through
    # Dexpace.attach_suppressed, and is discarded on success or on a returned error-status
    # response, which is a Response and not a throwable to attach to (stated, not dropped).
    class RetryStep
      include RetryStepHelpers

      private_class_method :new

      # Builds a frozen step.
      #
      # @param settings [RetrySettings] the shared configuration; the defaults when omitted
      # @param http_tracer_factory [#call] called once per operation with the cursor, answering
      #   an OBS-28 HTTP tracer; the frozen no-op NULL by default (R3, P6-7)
      # @param delay_override [#call, nil] RETRY-39's first tier: called with
      #   (attempt, response, error) and answering a delay in seconds or nil to decline; a
      #   raise or a bad answer is logged and falls through (RETRY-40)
      # @param should_retry [#call, nil] the caller's condition predicate, called with
      #   (failure, request) in place of the shared classifier; a raise aborts the call as
      #   RetryPredicateError (RETRY-40); it can never override the re-sendability gate (RETRY-8)
      # @param logger [Instrumentation::Logger] where RETRY-40's fallback and RETRY-41's clamp
      #   are reported, contained; Logger::NULL by default
      # @return [RetryStep] frozen
      # @raise [Dexpace::InvalidArgumentError] for a settings that is not a RetrySettings, a
      #   non-callable factory or hook, or a logger that is not a Logger
      def self.build(settings: RetrySettings.build, http_tracer_factory: NULL_TRACER_FACTORY,
                     delay_override: nil, should_retry: nil,
                     logger: Instrumentation::Logger::NULL)
        new(settings: settings, http_tracer_factory: http_tracer_factory,
            delay_override: delay_override, should_retry: should_retry, logger: logger,).freeze
      end

      # The default factory: the shared no-op, whatever the cursor.
      NULL_TRACER_FACTORY = ->(_cursor) { Instrumentation::NULL }
      private_constant :NULL_TRACER_FACTORY

      def initialize(settings:, http_tracer_factory:, delay_override:, should_retry:, logger:)
        initialize_retry_step(settings: settings, http_tracer_factory: http_tracer_factory,
                              delay_override: delay_override, should_retry: should_retry,
                              logger: logger,)
      end

      # 4c's optional declaration, read once at install: this is the Stages::RETRY pillar.
      #
      # @return [Dexpace::Pipeline::Stage]
      def stage
        Pipeline::Stages::RETRY
      end

      # One operation: attempts until a success, a non-retryable failure or a spent budget.
      #
      # @param request [Dexpace::Request] re-sent as the same object on every attempt (RETRY-44)
      # @param cursor [Dexpace::Pipeline::Cursor] forked for every drive
      # @return [Dexpace::Response] the terminal response, error status or not, unclosed
      # @raise [Exception] the terminal throwable, carrying the prior trail as suppressed
      # @raise [Dexpace::CancelledError] when the token is cancelled at an attempt boundary or
      #   during a wait
      # @raise [Dexpace::RetryPredicateError] when a caller's should_retry raised
      def call(request, cursor)
        run = Run.new(tracer: @http_tracer_factory.call(cursor), cursor: cursor,
                      max_retries: effective_max_retries(cursor), trail: [],)
        attempt = 1
        loop do
          terminal = attempt_once(run, request, attempt)
          return terminal unless terminal.nil?

          attempt += 1
        end
      end

      # The per-call locals one operation threads through its helpers (RETRY-42: on the stack,
      # never on the step), a private value so the helpers take one argument for the four.
      class Run < Data.define(:tracer, :cursor, :max_retries, :trail)
      end
      private_constant :Run

      private

      # One attempt, start to finish: the token check, the tracer, the drive, the decision and
      # -- on a retry -- the wait. Answers the terminal response, or nil for "again".
      def attempt_once(run, request, attempt)
        response, error = drive(run, request, attempt)
        return response if !response.nil? && !response.status.error?

        failure = failure_of(response, error)
        verdict = fenced(response) { decision(request, failure, attempt, run.max_retries) }
        return settle(run, response, failure, verdict) unless verdict == RETRY

        wait(run, attempt, response, failure)
      end

      # The retry path: the delay from the still-open response (fenced, RETRY-35), the tracer,
      # the trail, the close BEFORE the wait, then the wait on the settings' clock. On the
      # exception path the failure IS the error the override sees; on the response path the
      # override sees the response and no error (RETRY-39).
      #
      # @return [nil] always: the loop's "again"
      def wait(run, attempt, response, failure)
        delay = fenced(response) { resolve_delay(attempt, response, response ? nil : failure) }
        run.tracer.attempt_failed(run.cursor, failure, delay)
        run.trail << failure
        Dexpace.close_quietly(response, onto: failure)
        @settings.clock.sleep(delay, cancellation: run.cursor.cancellation)
      end

      # One drive: the token check at the attempt boundary (RETRY-23), the tracer, then the
      # downstream through a fresh fork. Only the drive's StandardError is rescued: the fatal
      # family propagates through the absent arm, unclassified and unretried (RETRY-25), and a
      # CancelledError from the check is not a drive failure and propagates as itself.
      #
      # @return [Array] the response and nil, or nil and the error
      def drive(run, request, attempt)
        run.cursor.cancellation.check!
        run.tracer.attempt_started(run.cursor, attempt)
        begin
          [run.cursor.fork.call(request), nil]
        rescue ::StandardError => error
          [nil, error]
        end
      end

      # RETRY-35's third ordering: whatever the block raises -- fatal family included -- the
      # open response is closed first and the raise propagates unchanged.
      def fenced(response)
        yield
      rescue ::Exception # rubocop:disable Lint/RescueException -- close, then re-raise unchanged (RETRY-25, RETRY-35)
        Dexpace.close_quietly(response, logger: @logger)
        raise
      end

      # The terminal path. A throwable is surfaced with the whole trail attached and, when the
      # budget is what stopped it, retries_exhausted first; a response is returned as it is, its
      # trail discarded, since a Response carries no suppressed trail to attach to (RETRY-34) --
      # the ProtocolError the tracer sees for an exhausted error status carries it instead.
      def settle(run, response, failure, verdict)
        return response if response && verdict == STOP

        attach_trail(failure, run.trail)
        run.tracer.retries_exhausted(run.cursor, failure) if verdict == EXHAUSTED
        return response if response

        raise failure, cause: nil # pipeline/7ce4431d: a carried error, never a bare raise
      end
    end
  end
end
