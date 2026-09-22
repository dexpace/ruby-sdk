# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # One call's exchange: steps 11 to 18 of the dispatch path, run inside a CHILD task of the
      # caller's own Async::Task under this call's `with_timeout`, and the cancellation bridge in
      # both directions (ASYNC-6, TRANSPORT-7, TRANSPORT-8, TRANSPORT-9). Every per-call value
      # lives here and on the Completer, never on the adapter (ASYNC-22, TRANSPORT-29).
      #
      # The bridge, as built. `Async::Task#cancel` on a task whose fiber is not current runs
      # `Fiber.scheduler.raise`, and `Fiber.scheduler` is nil on any OS thread but the reactor's
      # -- so a cancellation hook that reached the task directly would raise NoMethodError on the
      # canceller's thread and leave the exchange running, and the conformance suite cancels its
      # token from an OS thread. Instead every cancellation arrives through a Thread::Queue: the
      # token's hook settles the Completer cancelled and pushes its reason, `Future#cancel` settles
      # the Completer whose own hook pushes the reason, and a transient WATCHER task on the
      # caller's task pops the queue -- a scheduler-aware wait from inside the reactor, wakeable
      # from any thread -- and acts ON THE REACTOR'S THREAD: it cancels the exchange task while the
      # exchange is in flight, and closes the delivered response afterwards, which is what wakes a
      # consumer blocked in a body read. Closing the native body from the canceller's thread
      # instead corrupts the reactor's selector (measured: `IOError: stream closed in another
      # thread` out of the reactor itself). The queue is closed when the exchange ends undelivered
      # or when the delivered body is released, so the watcher wakes with nil and exits;
      # `transient: true` keeps a body a caller never closes from holding the caller's `Sync`
      # block open. A hook can still run after that close -- the source and the completer both
      # steal their hooks before they notify -- so the push is total over it (#signal) and a cancel
      # that lost the race against the exchange's own end never raises back into the canceller.
      #
      # `Async::Cancel` is not a StandardError and leaves this task through the
      # `rescue ::Exception` arm below, which re-raises it unchanged after settling the pivot
      # cancelled -- the repository's own shape for an exit that must run on a cancellation and
      # must not swallow it (typed_response.rb, redirect/step.rb, page/items.rb). No `$!` is read
      # anywhere. A private_constant of AsyncHTTP.
      class Exchange
        # @param completer [Dexpace::Async::Completer] the pivot this call settles
        # @param cancellation [Dexpace::Cancellation] the caller's token
        # @param client [Async::HTTP::Client] the client this origin's exchange goes through
        # @param native_request [Protocol::HTTP::Request] the mapped request
        # @param request [Dexpace::Request] the request the response answers
        # @param deadline [Float] this call's budget, in seconds
        # @param logger [Dexpace::Instrumentation::Logger]
        def initialize(completer:, cancellation:, client:, native_request:, request:, deadline:,
                       logger:)
          @completer = completer
          @cancellation = cancellation
          @client = client
          @native_request = native_request
          @request = request
          @deadline = deadline
          @logger = logger
          @queue = ::Thread::Queue.new
          @subscription = nil
          @task = nil
          @native = nil
          @adapted = nil
          @delivered = false
          @finishing = false
        end

        # The watcher task's annotation: what a reactor's task tree shows for it, and what the
        # adapter's suite reads to prove the watcher is gone once an exchange ends undelivered.
        WATCHER_ANNOTATION = "Dexpace::Transport::AsyncHTTP exchange watcher"

        # Spawns the watcher and then the exchange, both children of `caller_task` through its own
        # `#async` (on async 2.46 `Kernel#Async` inside a task delegates to the same call, so the
        # spelling is the honest one rather than a distinction the runtime still draws), and
        # returns; a child runs to its first suspension point before `async` returns, so a client
        # that answers without suspending has already settled the pivot when this method does.
        #
        # @param caller_task [Async::Task] the caller's current task
        # @return [void]
        def start(caller_task)
          caller_task.async(transient: true, annotation: WATCHER_ANNOTATION) { watch }
          @task = caller_task.async { |task| run(task) }
          nil
        end

        private

        # Steps 11 to 18. An already-cancelled pivot is noticed before any I/O; every exit closes
        # what was not delivered and settles what was not settled.
        def run(task)
          subscribe
          return finish { nil } if @completer.settled?

          task.with_timeout(@deadline) { perform }
          @finishing = true
        rescue ::Dexpace::CancelledError => error
          # Check-after-resume's own discovery path: the token was cancelled while the native
          # call was suspended and `check!` saw it before the watcher's cancel landed. Settled
          # through #request_cancel, never #fail, so Future#cancelled? reads true (ASYNC-6).
          finish { @completer.request_cancel(error.reason) }
        rescue ::StandardError => error
          # Step 17: everything else is wrapped retryable, or passed through when it is already a
          # Dexpace:: error; the token is asked first (TRANSPORT-3), and a cancelled token settles
          # a cancellation rather than a failure carrying one.
          finish { Errors.settle(@completer, error, phase: :connect, cancellation: @cancellation) }
        rescue ::Exception => error # rubocop:disable Lint/RescueException -- Async::Cancel < Exception: the runtime's own cancellation (a parent task cancelled, the reactor torn down, or the watcher acting on the pivot) must close the undelivered response and settle the pivot cancelled, then propagate unchanged so the task settles :cancelled (R13, TRANSPORT-8)
          finish { @completer.request_cancel(@cancellation.reason || :async_cancelled) }
          raise
        ensure
          net
        end

        # A cancellation raised inside one of #run's arms would have left the pivot unsettled:
        # the net that makes "the future always settles" a property of the code. The watcher
        # stays for the life of a DELIVERED response (the body's release ends it) and is released
        # here on every other exit.
        def net
          @completer.request_cancel(:async_cancelled) unless @completer.settled?
          release_watch unless @delivered
        end

        # The native call, check-after-resume, adaptation and delivery, under the deadline.
        def perform
          @native = @client.call(@native_request)
          @cancellation.check!
          @adapted = ResponseMapper.call(@native, request: @request, logger: @logger,
                                                  cancellation: @cancellation,
                                                  head: @request.method.token == "HEAD",
                                                  on_release: -> { release_watch },)
          # Step 18: Settlement's own "exactly one of response/error" makes a null success
          # unreachable (TRANSPORT-23); a lost race closes the response it was handed (SEAM-30).
          @delivered = @completer.fulfil(@adapted)
        end

        # The token drives the pivot AND the queue -- after delivery the pivot is settled and
        # `request_cancel` is a no-op, so the queue is what still reaches a body read -- and the
        # pivot drives the queue, for `Future#cancel`. Both hooks run inline when their subject is
        # already cancelled, and both may run AFTER the exchange has ended (#signal).
        def subscribe
          @subscription = @cancellation.on_cancel do |reason|
            @completer.request_cancel(reason)
            signal(reason)
          end
          @completer.on_cancel { |reason| signal(reason) }
        end

        # A hook's push, total over the exchange's end. `Cancellation::Source#cancel` and
        # `Completer#settle` each steal their hook list under their own mutex and run it outside,
        # on the CANCELLER's thread; an exchange that finished in between -- check-after-resume
        # saw the flag the cancel had already flipped, settled the pivot cancelled and closed this
        # queue through #release_watch, whose detach reached a list the source no longer held; or
        # a delivered body released in that same window -- has nothing left for the hook to do,
        # and `Thread::Queue#push` on the closed queue raises `ClosedQueueError`, which
        # `Hooks.notify` would hand back to the caller's own `Source#cancel` or `Future#cancel`.
        # A cancel that lost that race is not the caller's failure: the pivot is settled --
        # cancelled, or with a response whose body is already released -- and the token reads
        # cancelled, so the raise is swallowed here and nowhere else. A `closed?` check first
        # would be the same race one instruction later.
        def signal(reason)
          @queue.push(reason)
          nil
        rescue ::ClosedQueueError
          nil
        end

        # R13: the undelivered response is closed on EVERY exit, before the pivot is settled, so
        # a waiter that wakes finds the connection already released. Once adapted, the
        # Dexpace::Response owns the native body and a lost `fulfil` race has closed it already;
        # before that, the native body is the exchange's to close.
        def finish
          @finishing = true
          ::Dexpace.close_quietly(@native&.body, logger: @logger) if @adapted.nil?
          yield
        end

        # The watcher, on the reactor's thread: a reason means the pivot was cancelled -- from
        # the token, from Future#cancel, or from a pre-dispatch cancellation -- and nil means the
        # exchange ended or the delivered body was released. While the exchange is in flight the
        # task is cancelled, which is what reaches a native call blocked in a read or in the
        # pool's acquire (TRANSPORT-7); once the response is delivered the response itself is
        # closed, which is what reaches a consumer blocked in a body read, and never a delivered
        # response whose pivot was not cancelled (ASYNC-20). An exchange already in its exit path
        # is left to it: a cancel landing inside a close would leave the pivot to the ensure's net.
        #
        # The `cause:` is the SDK's own reason as an exception so the task's `Async::Cancel`
        # names it for whoever reads the task -- a debugger, the reactor's task tree -- rather
        # than the runtime's generic "Cancelling task!", which is what a non-Exception cause is
        # replaced with. Nothing in this adapter reads it back: by the time the watcher acts the
        # pivot is already settled cancelled with the reason (the token's hook settles it before
        # it pushes; Future#cancel settled it to run its hook at all), so #run's exit arm has
        # nothing left to settle and the reason a caller sees travelled through the token and the
        # completer, never through the Cancel.
        def watch
          reason = @queue.pop
          return if reason.nil?

          if @delivered
            ::Dexpace.close_quietly(@adapted, logger: @logger)
          elsif !@finishing
            @task&.cancel(cause: ::Dexpace::CancelledError.new(reason))
          end
        end

        # Idempotent: the queue's close wakes the watcher with nil, and Subscription#detach is a
        # no-op the second time. Reached from the exchange's own exit when nothing was delivered,
        # and from the delivered body's release otherwise -- through the mapper at once when
        # there is no body at all.
        def release_watch
          @queue.close
          @subscription&.detach
          nil
        end
      end

      private_constant :Exchange
    end
  end
end
