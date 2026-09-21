# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "rejected_error"
require_relative "timer"

module Dexpace
  module Async
    module Thread
      # A fixed-size ::Thread pool over a bounded ::Thread::SizedQueue: the first real
      # implementation of SEAM-18's caller-supplied executor duck type (`#post { }`) and of
      # Dexpace::Page::_Executor exactly (7c), the producer that settles phase 2's core-owned
      # pivot through Transport.async_over, and the owner of ASYNC-15..ASYNC-17's lifecycle over
      # Dexpace::Closeable. `size:` threads are created at construction and never grow or
      # shrink: a worker cannot die (see #run), so there is nothing to replace, and a pool whose
      # thread count changes has a capacity a caller cannot reason about (R12).
      #
      # There is no module-level default pool and no `.post` on the module
      # (concurrency-and-async/a1ec6ce4; SEAM-18): a caller constructs `Pool.build(size:)` in
      # their own code, where the size decision belongs, and closes it in an `ensure` -- the
      # README's first example, because the object that must be in an `ensure` is the one the
      # caller holds and a gem cannot write its consumer's `ensure`.
      #
      # NFR-11: no constant outside Dexpace:: appears anywhere in this class's public surface --
      # the threads and queues are private ivars with no readers, and #size / #queue_limit
      # return the Integers the caller passed, never @queue.max or @workers.length. This is the
      # gem where NFR-11 is cheapest to satisfy and easiest to break: a `#workers -> Array[Thread]`
      # accessor added for a diagnostic would fail gates:rbs_surface.
      #
      # See the gem README's "Cancellation and in-flight work" section for what happens to a
      # blocking send already running on a worker when its future is cancelled (ASYNC-7): it runs
      # to completion, and the SDK closes the orphaned result rather than delivering it.
      class Pool # rubocop:disable Metrics/ClassLength -- one executor, whose construction, submission, lifecycle and delay are one object's four faces (R12); a split would invent a second public constant
        include Dexpace::Closeable

        # A depth per worker, not an absolute capacity: "a worker may have eight units of work
        # waiting behind it before the pool rejects", scaling with whatever `size:` the caller
        # chose. Not tuned against a benchmark (design open question 1): the number that matters
        # is `size:`, which the caller states explicitly, and a depth chosen against one
        # machine's timing would read as measured when it is a burst-tolerance policy.
        QUEUE_DEPTH_PER_WORKER = 8

        # Long enough to outlive one in-flight HTTP send. A default rather than a required
        # keyword (design open question 2): a wrong `size:` is a starvation bug that persists
        # for the pool's whole life, while a wrong `shutdown_timeout:` costs at most one slow
        # shutdown, and a required keyword on a close-time budget would make the common
        # construction three keywords long for a value most callers have no opinion about. It
        # should exceed the wrapped transport's own read timeout, so an in-flight send finishes
        # inside it rather than being abandoned by the drain.
        DEFAULT_SHUTDOWN_TIMEOUT = 30.0

        # The thread-name prefix and the name every error message carries.
        DEFAULT_NAME = "dexpace-async-thread"

        # SEAM-25's lifecycle-event field keys, private: dexpace-conformance's assertion is
        # "close twice -> one event" and needs only the event name, and a public field key would
        # be an NFR-4 lock with one reader inside the gem that owns it (design open question 3).
        WORKER_COUNT_FIELD = "dexpace.executor.worker_count"
        private_constant :WORKER_COUNT_FIELD
        DRAINED_FIELD = "dexpace.executor.drained"
        private_constant :DRAINED_FIELD

        # Crosses a thread boundary: frozen Data, both members immutable by construction
        # (concurrency-and-async/2c743901, /16ceb098). The snapshot is Diagnostics.capture's
        # frozen Hash and the block is a Proc; the snapshot's VALUES are the caller's own objects
        # and are neither copied nor frozen -- a caller who puts a mutable object into fiber
        # storage shares that object across this hop (observability/65191069), which is the
        # caller's obligation under XCUT-11 and is stated in the README and in #post's YARD.
        Job = ::Data.define(:snapshot, :block)
        private_constant :Job

        # The worker's exit sentinel: non-nil, because Thread::Queue#pop returns nil for a
        # timeout, a closed queue and a pushed nil alike (design, verified fact 4).
        WORKER_EXITED = :worker_exited
        private_constant :WORKER_EXITED

        # What a #delay future settles with. `true`, matching phase 5a's Dexpace::Async.delay
        # (P5-52) so the two primitives are interchangeable at the call site, and never nil:
        # Completer#fulfil(nil) raises, because SEAM-16 forbids a success with no value.
        ELAPSED = true
        private_constant :ELAPSED

        private_class_method :new

        # The one entry point. `size:` is required and has no default -- SEAM-18's own argument
        # one level down: the right number is a function of the caller's service, its p99 and
        # its connection budget, none of which the SDK can see, and a wrong guess is the
        # starvation SEAM-18 names. `queue_limit:` defaults to `size * QUEUE_DEPTH_PER_WORKER`,
        # derived AFTER `size` is validated so `Pool.build(size: nil)` names the keyword rather
        # than raising NoMethodError from the default. Every failure is
        # Dexpace::InvalidArgumentError naming the offending keyword.
        #
        # @param size [Integer] the number of worker threads, positive; created now, never grown
        # @param queue_limit [Integer, nil] the bounded queue's depth; nil derives it
        # @param shutdown_timeout [Numeric] #close's whole budget in seconds, non-negative
        # @param name [String] the thread-name prefix and the name error messages carry
        # @param logger [Dexpace::Instrumentation::Logger] where the shutdown event and a task
        #   defect's diagnostic go; Logger::NULL emits nothing
        # @param clock [Dexpace::Clock, #monotonic] the deadline arithmetic's source (CFG-16)
        # @return [Dexpace::Async::Thread::Pool]
        # @raise [Dexpace::InvalidArgumentError] naming the keyword that failed
        def self.build(size:, queue_limit: nil, shutdown_timeout: DEFAULT_SHUTDOWN_TIMEOUT,
                       name: DEFAULT_NAME, logger: Dexpace::Instrumentation::Logger::NULL,
                       clock: Dexpace::Clock::SYSTEM)
          size = positive_integer!(:size, size)
          queue_limit = positive_integer!(:queue_limit,
                                          queue_limit || (size * QUEUE_DEPTH_PER_WORKER),)
          new(size: size, queue_limit: queue_limit,
              shutdown_timeout: non_negative_numeric!(:shutdown_timeout, shutdown_timeout),
              name: non_empty_string!(:name, name),
              logger: responding!(:logger, logger, :event),
              clock: responding!(:clock, clock, :monotonic),)
        end

        def self.positive_integer!(keyword, value)
          return value if value.is_a?(::Integer) && value.positive?

          raise Dexpace::InvalidArgumentError,
                "#{keyword} must be a positive Integer, got #{value.inspect}"
        end
        private_class_method :positive_integer!

        def self.non_negative_numeric!(keyword, value)
          return value if value.is_a?(::Numeric) && !value.negative?

          raise Dexpace::InvalidArgumentError,
                "#{keyword} must be a non-negative Numeric, got #{value.inspect}"
        end
        private_class_method :non_negative_numeric!

        def self.non_empty_string!(keyword, value)
          return value if value.is_a?(::String) && !value.empty?

          raise Dexpace::InvalidArgumentError,
                "#{keyword} must be a non-empty String, got #{value.inspect}"
        end
        private_class_method :non_empty_string!

        def self.responding!(keyword, value, method_name)
          return value if value.respond_to?(method_name)

          raise Dexpace::InvalidArgumentError,
                "#{keyword} must respond to ##{method_name}, got #{value.class}"
        end
        private_class_method :responding!

        # The Integers the caller passed, never the queue's or the array's own count (NFR-11).
        attr_reader :size, :queue_limit

        # The name every worker thread carries and every error message names.
        attr_reader :name

        # Keyword-only, private: `.build` validates and this constructs. The timer is cheap to
        # hold from the start -- no thread exists until the first positive #delay (R11).
        def initialize(size:, queue_limit:, shutdown_timeout:, name:, logger:, clock:)
          @size = size
          @queue_limit = queue_limit
          @shutdown_timeout = shutdown_timeout
          @name = name
          @logger = logger
          @clock = clock
          @queue = ::Thread::SizedQueue.new(queue_limit)
          @exits = ::Thread::Queue.new
          @timer = Timer.new(name: name, on_error: lambda { |error|
            report_failure(error)
          }, clock: clock,)
          @workers = ::Array.new(size) { |index| spawn_worker(index) }
          initialize_closeable(owned: true)
        end

        # SEAM-18's duck type, and Dexpace::Page::_Executor exactly: `() { () -> void } -> void`,
        # returning nil -- a handle returned through an interface that says the value is not to
        # be used would be a surface in one NFR-4 artifact and not the other (R12). Never blocks
        # the calling thread, a pool worker re-posting to its own pool included (P8-23): the
        # queue's non-blocking push turns a full queue into RejectedError rather than a parked
        # producer, which is what makes ASYNC-2's "saturated" antecedent live at all.
        #
        # The caller's diagnostic context is captured HERE, per submission (ASYNC-10), never at
        # construction, and installed on the worker for the block's duration (ASYNC-8, ASYNC-9);
        # the snapshot's values are shared, not copied (see Job). See the README's "Cancellation
        # and in-flight work" for what a cancel does to a block already running (ASYNC-7).
        #
        # @yield [] the unit of work; runs on a pool worker with the caller's context installed
        # @return [nil]
        # @raise [ArgumentError] without a block -- a programmer error, refused before the queue
        # @raise [Dexpace::ClosedError] if the pool is closed (SEAM-15)
        # @raise [Dexpace::Async::Thread::RejectedError] if the bounded queue is full
        def post(&block)
          raise ::ArgumentError, "post requires a block" unless block
          raise Dexpace::ClosedError, "#{@name} is closed" if closed?

          job = Job.new(snapshot: Dexpace::Instrumentation::Diagnostics.capture, block: block)
          begin
            @queue.push(job, true)
          rescue ::ThreadError
            raise RejectedError, "#{@name}: queue full (limit #{@queue_limit}, #{@size} workers)"
          rescue ::ClosedQueueError
            raise Dexpace::ClosedError, "#{@name} is closed"
          end
          nil
        end

        # ASYNC-18's non-blocking scheduled delay, backed by the pool's one lazily created timer
        # thread and shared across every outstanding delay (R11). Settles with `true`, as phase
        # 5a's Dexpace::Async.delay does, so the two are interchangeable at the call site; the
        # primitive's whole content is "later" and a richer value would be an NFR-4 lock with no
        # consumer.
        #
        # "Without blocking a thread" holds for the caller's thread and every pool worker, and
        # not absolutely: one named "<name> timer" thread is parked for the interval (P8-25). A
        # caller under a Fiber.scheduler who wants the zero-thread reading uses
        # Dexpace::Async.delay -- unavailable to a pool worker regardless, since Fiber.scheduler
        # is per thread (design, verified fact 15). A caller's #on_settle on the returned future
        # runs on the TIMER thread, not on a pool worker: a handler that blocks is blocking every
        # later delay. A handler that closes the pool completes the close there -- the timer
        # thread is not joined by itself, the other outstanding delays are failed and the
        # shutdown event is emitted (P8-76) -- as a task that closes its own pool does on its
        # worker.
        #
        # A CLOSED pool fails the future and does not raise: #delay is a method that promised a
        # future, and ASYNC-2 forbids delivering a detectable construction failure synchronously
        # from one, naming "worker-pool rejection (a saturated/shut-down executor)" as this case.
        # #post escapes that rule because phase 2's bridge routes its raise to Completer#fail;
        # #delay has no router and does the routing itself. The two argument raises stay raises:
        # a negative or non-Numeric duration is a programming error in the call, and ASYNC-18's
        # own wording is "MUST reject a negative delay" (R11's fifth clause).
        #
        # @param duration [Numeric] seconds, non-negative; zero settles before this returns and
        #   spawns nothing
        # @return [Dexpace::Async::Future] settled with true after the delay, or already failed
        #   with Dexpace::ClosedError on a closed pool
        # @raise [Dexpace::InvalidArgumentError] for a negative or non-Numeric duration, before
        #   any timer thread exists
        def delay(duration)
          validate_duration!(duration)
          completer = Dexpace::Async::Completer.new
          if closed?
            completer.fail(closed_error)
          elsif duration.zero?
            completer.fulfil(ELAPSED)
          else
            schedule(completer, duration)
          end
          completer.future
        end

        private

        def validate_duration!(duration)
          unless duration.is_a?(::Numeric)
            raise Dexpace::InvalidArgumentError, "duration must be Numeric, got #{duration.class}"
          end
          return unless duration.negative?

          raise Dexpace::InvalidArgumentError, "duration must not be negative, got #{duration}"
        end

        def closed_error = Dexpace::ClosedError.new("#{@name} is closed")

        # One timer entry per positive delay; cancelling the future removes it and wakes the
        # timer, so no scheduler thread is held for a delay nobody wants (ASYNC-18). A #stop
        # racing this schedule refuses the entry through on_shutdown, so the future is failed
        # rather than left hanging.
        def schedule(completer, duration)
          entry = @timer.schedule(
            duration,
            on_fire: -> { completer.fulfil(ELAPSED) },
            on_shutdown: -> { completer.fail(closed_error) },
          )
          completer.on_cancel { @timer.cancel(entry) }
          nil
        end

        # The first of the gem's two bounded ::Thread.new sites: exactly `size` of these, in one
        # private method, never in a loop over work (concurrency-and-async/df658d73). Everything
        # about the thread is set INSIDE it -- the name, so a thread dump never shows an
        # anonymous worker, and report_on_exception, because setting it from outside is a race
        # (design, verified fact 10).
        def spawn_worker(index)
          ::Thread.new do
            ::Thread.current.name = "#{@name} worker #{index}"
            ::Thread.current.report_on_exception = false
            # R8/R9, boundary 1 of 2: clear whatever this worker inherited from the fiber that
            # called Pool.build, once, before the first task -- the construction floor. Boundary
            # 2 is #run's ensure, and neither is sufficient alone (P8-20).
            clear_fiber_storage
            begin
              # A suspension point (concurrency-and-async/611b9392), and nil is the ONE exit: the
              # queue is closed exactly once by #release, nothing ever pushes a nil and no timeout
              # is used here, so a nil pop means "closed and drained" unambiguously.
              while (job = @queue.pop)
                run(job)
              end
            ensure
              @exits << WORKER_EXITED
            end
          end
        end

        # P8-22: rescues ::Exception and the worker never dies. RECOV-2's "rescue Exception,
        # re-raise anything outside StandardError" is departed from deliberately: on a worker
        # thread "re-raise" means the thread dies silently (design, verified facts 10 and 11) and
        # the pool is permanently one worker smaller with no signal, and the caller's failure
        # channel was already settled by the block itself before this net could see anything --
        # what reaches here is a defect IN the block, emitted as a diagnostic rather than demoted
        # into any caller's result. Interrupt is the case worth naming: Ctrl-C is delivered to
        # the main thread, so swallowing it here discards nothing.
        def run(job)
          Dexpace::Instrumentation::Diagnostics.with(job.snapshot) { job.block.call }
        rescue ::Exception => error # rubocop:disable Lint/RescueException -- P8-22: the worker never dies; see the method comment
          report_failure(error)
        ensure
          # R8/R9, boundary 2 of 2, not redundant with the thread-start clear: Diagnostics.with
          # restores only (prior.keys | snapshot.keys), so a key the BLOCK itself writes -- an
          # #on_settle handler, a caller's interceptor, a sink -- is in neither set and would
          # survive onto the next caller's task (measured: {tenant: "A-LEAK", "trace.id":
          # "CALLER-B"} on the next task). After the thread-start clear the worker's prior map is
          # provably {} (nil-valued keys on the 3.2 floor, which every reader skips), so
          # re-running the line IS "restore prior". One Fiber.current.storage read per task.
          clear_fiber_storage
        end

        # Per key, through Fiber[]= alone, never Fiber#storage= (which warns on every call on
        # every supported Ruby). Fiber.current.storage returns a fresh Hash (verified fact 5), so
        # this iterates a copy and writes to the live storage; on the 3.2 floor the write retains
        # the key with a nil value (P5-72), which Fiber[] and Diagnostics.capture both read as
        # absent. The untyped read is core's own spelling (Diagnostics.current_storage): rbs types
        # the keys `interned` and `Fiber.[]=` takes a Symbol.
        def clear_fiber_storage
          storage = ::Fiber.current.storage #: untyped
          storage&.each_key { |key| ::Fiber[key] = nil }
          nil
        end

        # §3.7's second disposal route for a failure with no primary to attach to: one ERROR
        # diagnostic under INSTRUMENTATION_HOOK, inside Instrumentation.contain, so a raising
        # sink cannot kill the thread reporting through it (OBS-20). Shared by the worker net
        # and the timer's, which is why the timer takes it as `on_error:`.
        def report_failure(error)
          contained do
            @logger.event(Dexpace::Instrumentation::Severity::ERROR)
              .event(Dexpace::Instrumentation::Events::INSTRUMENTATION_HOOK)
              .cause(error)
              .emit
          end
        end

        # Dexpace::Closeable's latch runs this on the winning #close only, after the @closed flip
        # and with the mutex released (design, "Thread-safety proof obligations"). The sequence
        # is R12's: close the queue (stop accepting; queued work still drains, verified fact 3),
        # stop the timer and fail its outstanding delays, wait for every worker's exit sentinel
        # within ONE budget shared by both waits, then emit SEAM-25's lifecycle event exactly
        # once -- the event phase 2 postponed, given its first real subject here. The drain's
        # outcome rides on the event, not the return value: #close is Closeable's method and
        # phase 2 fixes it at nil for every closeable (P8-24 for the absent cancellation:).
        # It completes from any thread, the pool's own two kinds included: neither the timer's
        # stop nor the drain ever joins the thread it is running on (P8-76).
        def release
          deadline = @clock.monotonic + @shutdown_timeout
          @queue.close
          stop_timer(deadline)
          drained = drain_workers(deadline)
          emit_shutdown(drained)
          nil
        end

        # The timer shares the workers' single close budget rather than getting one of its own,
        # so #close is bounded by shutdown_timeout in total.
        def stop_timer(deadline)
          @timer.stop([deadline - @clock.monotonic, 0.0].max)
        end

        # Bounded and sentinel-carrying: @exits.pop's return alone cannot distinguish "the
        # budget elapsed" from "the queue closed" from "a worker exited" (verified fact 4), so
        # the clock is re-read on every iteration rather than trusted to the pop, and a spent
        # budget returns before any queue wait -- which is the one branch a fake clock can drive.
        # The workers are then joined within what is left of the budget, so a drained pool has
        # no thread in Thread.list by the time #close returns, not merely no thread about to
        # exit.
        #
        # A #close issued from INSIDE a task counts the worker running it as exited and never
        # joins it (P8-76): its sentinel cannot arrive until #release returns, so waiting for it
        # burned the whole budget and reported the drain as failed on every such close, and a
        # self-join raises ThreadError. That worker exits by itself once the task returns,
        # running whatever the closed queue still holds first, exactly as after any other close.
        def drain_workers(deadline) # rubocop:disable Naming/PredicateMethod -- a command reporting whether the drain completed inside the budget, on the event's own field
          others = other_workers
          remaining = others.size
          while remaining.positive?
            budget = deadline - @clock.monotonic
            return false if budget <= 0

            exited = @exits.pop(timeout: budget)
            return false if exited.nil? && @clock.monotonic >= deadline

            remaining -= 1 if exited
          end
          others.each { |worker| worker.join([deadline - @clock.monotonic, 0.0].max) }
          true
        end

        # Every worker but the one #close is running on, if it is running on one.
        def other_workers
          closer = ::Thread.current
          @workers.reject { |worker| worker.equal?(closer) }
        end

        # SEAM-25's lifecycle event: INFO, the worker count and whether the drain completed
        # inside the budget, inside Instrumentation.contain so a raising sink cannot fail #close
        # (OBS-20, ASYNC-15's "safe").
        def emit_shutdown(drained)
          contained do
            @logger.event(Dexpace::Instrumentation::Severity::INFO)
              .event(Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN)
              .field(WORKER_COUNT_FIELD, @size)
              .field(DRAINED_FIELD, drained)
              .emit
          end
        end

        # The one log-emission fence in the gem: Instrumentation.contain under the log-site
        # diagnostic name, so a raising sink produces a WARNING diagnostic and never a raise, and
        # a failure of THAT is swallowed (OBS-20, XCUT-20).
        def contained(&)
          Dexpace::Instrumentation.contain(
            @logger, event: Dexpace::Instrumentation::Events::INSTRUMENTATION_LOG, &
          )
        end
      end
    end
  end
end
