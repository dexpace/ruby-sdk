# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "retry_step_helpers"
require_relative "../async/completer"
require_relative "../async/future"
require_relative "../async/delay"
require_relative "../error/cancelled_error"
require_relative "../error/seam_error"
require_relative "../pipeline/stages"
require_relative "../instrumentation/http_tracer"
require_relative "../instrumentation/logger"

module Dexpace
  module Resilience
    # The stage-based retry step, asynchronous half: the same policy, the same decision and the
    # same delay resolution as RetryStep (one RetryStepHelpers, so the two cannot drift, design
    # §11.12) over 4c's _AsyncStep contract -- #call returns a Dexpace::Async::Future and every
    # downstream drive is a fork's future. Declares Stages::RETRY, forks for every drive
    # (pipeline/86343352) and writes no cursor state.
    #
    # RETRY-30: an ITERATIVE trampoline, never a recursive one. Each #call allocates one private
    # Pump holding the per-call state (RETRY-42, RECOV-28: nothing on the step). The pump runs
    # attempts in a `loop` on whatever frame is driving it; a downstream future or a delay
    # future that settles INLINE -- which every scripted transport does, and which Async.delay
    # does for a zero-length delay (RETRY-31) -- does not call back into a nested attempt but
    # flips a RE-ARM flag under the pump's mutex, and the loop already running picks the next
    # attempt up when the current one returns. Only a future that settles LATER, on another
    # thread or a scheduler fiber, starts the loop again from its callback, on a fresh stack.
    # Measured: the plan's recursive shape overflowed at ~1500 attempts on every interpreter;
    # this one is flat at 2000 (async_retry_step_test.rb asserts the depth, not just the count).
    #
    # R2's route, as built: a positive delay goes through 5a's Async.delay, which unmounts the
    # fiber under a registered Fiber.scheduler and RAISES Dexpace::SeamError synchronously with
    # none -- the raise is caught by RETRY-33's fence and fails the returned future, carrying the
    # prior trail; a zero-length delay completes inline and re-arms the pump without a frame; and
    # nothing here installs, reads or shuts down a scheduler (RETRY-45). Never Clock#sleep: a
    # blocking wait on the async path is what RETRY-31 and RETRY-26 forbid.
    #
    # RETRY-33: every callback body runs inside one fence that closes any open retryable
    # response and fails the completer on a StandardError -- a throwing predicate, delay
    # computation, log call, tracer callback or scheduler rejection each completes the future
    # exceptionally rather than escaping into whoever settled the downstream future and leaving
    # the returned future hanging. The fatal family is re-raised after the completer is failed
    # (RETRY-25), because a hung future is not an acceptable price for propagating it.
    #
    # RETRY-32: once the returned future is settled or cancelled -- by the caller, by a deadline
    # -- no further attempt is launched, a pending delay is cancelled, and a response arriving
    # from an attempt still in flight is closed rather than leaked. RETRY-23 / RECOV-27: the
    # cursor's token is checked at the top of every attempt and, on cancellation during a wait,
    # cancels the pending delay and fails the future with the CancelledError, the trail attached.
    class AsyncRetryStep
      include RetryStepHelpers

      private_class_method :new

      # Builds a frozen step; the keywords are RetryStep.build's, with the same meanings.
      #
      # @param settings [RetrySettings]
      # @param http_tracer_factory [#call] called once per operation with the cursor
      # @param delay_override [#call, nil] RETRY-39's first tier
      # @param should_retry [#call, nil] the caller's condition predicate
      # @param logger [Instrumentation::Logger]
      # @return [AsyncRetryStep] frozen
      # @raise [Dexpace::InvalidArgumentError] as RetryStep.build
      def self.build(settings: RetrySettings.build, http_tracer_factory: NULL_TRACER_FACTORY,
                     delay_override: nil, should_retry: nil,
                     logger: Instrumentation::Logger::NULL)
        new(settings: settings, http_tracer_factory: http_tracer_factory,
            delay_override: delay_override, should_retry: should_retry, logger: logger,).freeze
      end

      NULL_TRACER_FACTORY = ->(_cursor) { Instrumentation::NULL }
      private_constant :NULL_TRACER_FACTORY

      def initialize(settings:, http_tracer_factory:, delay_override:, should_retry:, logger:)
        initialize_retry_step(settings: settings, http_tracer_factory: http_tracer_factory,
                              delay_override: delay_override, should_retry: should_retry,
                              logger: logger,)
      end

      # 4c's optional declaration: the Stages::RETRY pillar.
      #
      # @return [Dexpace::Pipeline::Stage]
      def stage
        Pipeline::Stages::RETRY
      end

      # One operation, as a future that settles with the terminal response or fails with the
      # terminal throwable (its trail attached), or with the CancelledError of a cancelled token.
      #
      # @param request [Dexpace::Request] re-sent as the same object on every attempt (RETRY-44)
      # @param cursor [Dexpace::Pipeline::Cursor] forked for every drive
      # @return [Dexpace::Async::Future]
      def call(request, cursor)
        Pump.new(settings: @settings, http_tracer_factory: @http_tracer_factory,
                 delay_override: @delay_override, should_retry: @should_retry, logger: @logger,
                 request: request, cursor: cursor,).start
      end

      # The per-call state and the trampoline (RETRY-30). One instance per #call, carrying the
      # step's five configuration values and the same helpers, reachable from nothing but the
      # callbacks it registers; a private_constant with a sig/ mirror. Over the class-length
      # default by fifteen lines, and deliberately one class: the re-arm protocol, the fence and
      # the terminal paths share the completer and the flags, and splitting them across objects
      # would scatter the one invariant the trampoline rests on (the recorded exception
      # .rubocop.yml's metric note asks for).
      class Pump # rubocop:disable Metrics/ClassLength -- one per-call state machine, see above
        include RetryStepHelpers

        def initialize(settings:, http_tracer_factory:, delay_override:, should_retry:, logger:,
                       request:, cursor:)
          initialize_retry_step(settings: settings, http_tracer_factory: http_tracer_factory,
                                delay_override: delay_override, should_retry: should_retry,
                                logger: logger,)
          @request = request
          @cursor = cursor
          @completer = Dexpace::Async::Completer.new
          @tracer = Instrumentation::NULL
          @max_retries = 0
          @attempt = 1
          @trail = []
          @mutex = ::Thread::Mutex.new
          @running = false
          @rearm = false
          @pending_delay = nil
        end

        # Arms the cancellation bridges, runs the first attempt, and returns the future.
        def start
          guarded(nil) do
            @tracer = @http_tracer_factory.call(@cursor)
            @max_retries = effective_max_retries(@cursor)
            @completer.on_cancel { @pending_delay&.cancel }
            subscription = @cursor.cancellation.on_cancel { |reason| abort(reason) }
            @completer.future.on_settle { subscription.detach }
            resume
          end
          @completer.future
        end

        private

        # The re-arm protocol (RETRY-30), called from the frame that wants the next attempt to
        # run. When a pump loop is already running on some frame, set the flag and return --
        # that loop picks the attempt up when its current one returns; otherwise become that
        # loop, and keep launching until nothing re-armed it. The flags flip under the mutex
        # only, never across an attempt, so a settlement from another thread cannot lose its
        # re-arm between the loop's last check and its exit.
        def resume
          return unless claim(:start)

          loop do
            launch
            break unless claim(:continue)
          end
        end

        # :start claims the loop when none runs (else re-arms and answers false); :continue
        # consumes a re-arm (else releases the loop and answers false).
        def claim(step)
          @mutex.synchronize do
            if step == :start && @running
              @rearm = true
              false
            elsif step == :start
              @running = true
            elsif @rearm
              @rearm = false
              true
            else
              @running = false
            end
          end
        end

        # One attempt: the token check, the tracer, a fresh fork, and the settlement callback --
        # which runs inline when the downstream settled synchronously.
        def launch
          return if @completer.settled?

          guarded(nil) do
            @cursor.cancellation.check!
            @tracer.attempt_started(@cursor, @attempt)
            @cursor.fork.call(@request).on_settle { |settlement| settled(settlement) }
          end
        end

        # A downstream settlement: RETRY-32's abandoned-attempt close first, then a terminal
        # success or a terminal fatal, then the decision.
        def settled(settlement)
          response = settlement.response
          guarded(response) do
            next Dexpace.close_quietly(response, logger: @logger) if @completer.settled?
            next if delivered?(response, settlement.error)

            failure = failure_of(response, settlement.error)
            verdict = decision(@request, failure, @attempt, @max_retries)
            next finish(response, failure, verdict) unless verdict == RETRY

            retry_after(response, settlement.error, failure)
          end
        end

        # The two settlements that need no decision: a non-error response is delivered, and a
        # fatal-family error -- which on this path arrives as a settlement and meets no rescue
        # arm -- is delivered unclassified, unretried and with no trail attached (RETRY-25),
        # rather than reaching the capability query a lying subclass could answer.
        def delivered?(response, error)
          if error.nil?
            return false if response.nil? || response.status.error?

            @completer.fulfil(response)
          else
            return false if error.is_a?(::StandardError)

            @completer.fail(error)
          end
          true
        end

        # The retry path: the delay from the still-open response, the tracer, the trail, the
        # close (RETRY-35), then the wait.
        def retry_after(response, error, failure)
          delay = resolve_delay(@attempt, response, error)
          @tracer.attempt_failed(@cursor, failure, delay)
          @trail << failure
          Dexpace.close_quietly(response, onto: failure)
          wait(delay)
        end

        # The terminal path, mirroring RetryStep#settle: a response is delivered as it is, a
        # throwable with the trail attached, retries_exhausted first when the budget stopped it.
        def finish(response, failure, verdict)
          return @completer.fulfil(response) if response && verdict == STOP

          attach_trail(failure, @trail)
          @tracer.retries_exhausted(@cursor, failure) if verdict == EXHAUSTED
          response ? @completer.fulfil(response) : @completer.fail(failure)
        end

        # RETRY-31 / R2: the wait is Async.delay's future. Zero-length settles inline, so the
        # callback runs now and re-arms the running loop; positive under a scheduler settles on
        # the scheduler's fiber, whose callback starts a fresh loop; positive with no scheduler
        # raises SeamError here, synchronously, into the fence around this method's caller.
        def wait(delay)
          @attempt += 1
          future = Dexpace::Async.delay(delay)
          @pending_delay = future
          future.on_settle do |elapsed|
            @pending_delay = nil
            guarded(nil) do
              if elapsed.error
                @completer.fail(attach_trail(elapsed.error, @trail))
              elsif !@completer.settled? # RETRY-32
                resume
              end
            end
          end
        end

        # RETRY-23 / RECOV-27 during a wait: cancel the pending timer and surface the
        # cancellation; a no-op once the future is settled.
        def abort(reason)
          return if @completer.settled?

          @pending_delay&.cancel(reason)
          @completer.fail(attach_trail(Dexpace::CancelledError.new(reason), @trail))
        end

        # RETRY-33's fence, and RETRY-25's: close the open response, fail the future, and let a
        # fatal-family error propagate after the future is settled. The trail travels with the
        # failure the fence reports.
        def guarded(response)
          yield
        rescue ::StandardError => error
          Dexpace.close_quietly(response, onto: error)
          @completer.fail(attach_trail(error, @trail))
        rescue ::Exception => error # rubocop:disable Lint/RescueException -- RETRY-25 with RETRY-33: fail, then re-raise unchanged
          Dexpace.close_quietly(response, logger: @logger)
          @completer.fail(error)
          raise
        end
      end
      private_constant :Pump
    end
  end
end
