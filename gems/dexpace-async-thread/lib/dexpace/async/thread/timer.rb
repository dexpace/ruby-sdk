# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Async
    module Thread
      # R11's implementation, and a private_constant of Dexpace::Async::Thread: one lazily created
      # ::Thread per instance, named "<name> timer", parked on a wake queue against the NEAREST
      # deadline and re-parked after every wake. The queue is a wake signal and never a value
      # channel -- phase 2's reason for the pivot's own queue, and the third load-bearing
      # appearance of Thread::Queue#pop's nil ambiguity in this repository (design, verified
      # fact 4): the thread reads `closed?` after every pop and nothing else off it.
      #
      # It knows nothing about futures. #schedule takes two opaque callbacks -- what "fired" and
      # what "shut down" mean are the caller's (Pool#delay settles a Completer either way) -- and
      # a third, `on_error:`, is the containment every callback runs under: the timer thread
      # rescues ::Exception around each callback and reports it there rather than dying, for
      # the same reason a pool worker never dies (P8-22, extended to the second thread the gem
      # owns): a dead timer strands every later delay and turns the next #stop into a raise
      # through the join, and Thread#report_on_exception writes to $stderr past every gate.
      #
      # It is the gem's second carrier of a caller's diagnostic context, and it carries it the
      # way the worker does (P8-20, extended to this thread by P8-78): #schedule captures the
      # scheduling fiber's context per entry (ASYNC-10's per-submission point), every callback
      # runs under Diagnostics.with over that snapshot (ASYNC-8, ASYNC-9), and the timer thread
      # clears its own storage once at start and again after every callback, so a #on_settle or
      # #then on a delay future sees the context of the caller who asked for THAT delay -- never
      # the first caller's, which ::Thread.new copied into this thread when it was spawned, and
      # never a key an earlier handler wrote. The shutdown callback runs on whichever thread
      # stopped the timer under the same install-and-restore, and that thread's storage is not
      # this timer's to clear.
      #
      # The mutex is held across a list insert, a list delete, a `first` read, the stop flag
      # and the lazy thread creation -- never across #pop(timeout:), a callback or a Completer
      # settle (design, "Thread-safety proof obligations"): Thread::Mutex ownership is per fiber
      # and non-reentrant, so a lock held across a suspension point deadlocks two fibers of one
      # thread. The wait is computed inside the lock and performed outside it.
      class Timer # rubocop:disable Metrics/ClassLength -- one thread, its deadline list and its two context boundaries; the boundaries belong to the thread they clear (P8-78) and a split would invent a second private constant for half a thread
        # One scheduled deadline, the scheduling caller's captured diagnostic context and the
        # two outcomes. Crosses the timer thread's boundary: frozen Data, every member immutable
        # by construction (concurrency-and-async/2c743901); the snapshot is Diagnostics.capture's
        # frozen Hash, whose VALUES are the caller's own objects, shared as Pool::Job shares them.
        Entry = ::Data.define(:deadline, :snapshot, :on_fire, :on_shutdown)
        private_constant :Entry

        # @param name [String] the pool's name; the thread is "<name> timer" in a thread dump
        # @param on_error [Proc] `->(error)`, total, run for a callback that raised
        # @param clock [#monotonic] the monotonic source every deadline is measured against
        def initialize(name:, on_error:, clock:)
          @name = name
          @on_error = on_error
          @clock = clock
          @mutex = ::Thread::Mutex.new
          @entries = [] #: Array[Entry]
          @wake = ::Thread::Queue.new
          @thread = nil
          @stopped = false
        end

        # Registers a deadline `delay` seconds from now, spawning the timer thread on the first
        # call. After #stop the entry is refused through its own `on_shutdown` at once and no
        # thread is spawned -- the backstop for a #delay that read the pool's latch open a moment
        # before #close ran.
        #
        # The calling fiber's diagnostic context is captured HERE, per entry (ASYNC-10): this
        # runs synchronously inside Pool#delay on the caller's own thread, so what it reads is
        # the context of the caller who asked for this delay, and the callbacks reinstate it.
        #
        # @return [Object] an opaque handle for #cancel
        def schedule(delay, on_fire:, on_shutdown:)
          entry = Entry.new(deadline: @clock.monotonic + delay,
                            snapshot: Dexpace::Instrumentation::Diagnostics.capture,
                            on_fire: on_fire, on_shutdown: on_shutdown,)
          refused = @mutex.synchronize do
            if @stopped
              true
            else
              @entries << entry
              @entries.sort_by!(&:deadline)
              @thread ||= spawn_thread
              false
            end
          end
          if refused
            shut_down(entry)
          else
            wake
          end
          entry
        end

        # Removes a scheduled entry so it never fires, and wakes the thread so it re-parks against
        # the next real deadline rather than holding a slot for a cancelled one (ASYNC-18's "no
        # scheduler thread is held"). Identity, never Data equality: two entries with one deadline
        # are two entries.
        def cancel(entry)
          @mutex.synchronize { @entries.delete_if { |scheduled| scheduled.equal?(entry) } }
          wake
          nil
        end

        # Stops the timer thread, if one was ever spawned (a pool that only ever scheduled zero
        # delays never spawns one), and fails every entry that never fired through its own
        # on_shutdown callback rather than firing it early -- ASYNC-18's "no scheduler thread is
        # held" applied to shutdown, and the design's "not completed early".
        #
        # The join is BOUNDED by the caller's remaining budget and never a bare #join: XCUT-13 and
        # design §3.7 forbid an unbounded wait in a close path for this gem by name, and the timer
        # is one of the pool's owned resources, not an exception to it. The thread body cannot
        # raise (every callback is guarded and the body itself is netted), so the join never
        # re-raises a dead thread's exception past #close. The entries are failed whether or not
        # the join completed: a caller blocked in #value on a delay that will never fire is the
        # one outcome worse than a slow close.
        #
        # A #stop issued FROM the timer thread -- a caller's #on_settle handler on a delay future
        # that closes the pool, the README's grace-period idiom -- skips the join: Thread#join on
        # the current thread raises ThreadError, which would escape #close with the latch already
        # flipped, no event emitted and every other outstanding delay stranded (P8-76). The thread
        # needs no join to stop: the wake queue is closed here, the next pop answers nil at once,
        # and #run exits as soon as the handler returns. The leftovers are failed on this thread
        # as on any other.
        def stop(timeout)
          thread, leftover = @mutex.synchronize do
            @stopped = true
            taken = @entries
            @entries = []
            [@thread, taken]
          end
          @wake.close
          thread&.join(timeout) unless thread.equal?(::Thread.current)
          leftover.each { |entry| shut_down(entry) }
          nil
        end

        private

        # The gem's second and last ::Thread.new: at most one per pool, on the first positive
        # delay, never in a loop (concurrency-and-async/df658d73). Named and netted INSIDE the
        # body, as Pool#spawn_worker is: naming from outside leaves a gap in which a thread dump
        # shows an anonymous thread, and report_on_exception set from outside is a race.
        def spawn_thread
          ::Thread.new do
            ::Thread.current.name = "#{@name} timer"
            ::Thread.current.report_on_exception = false
            # P8-20's boundary 1 of 2, for this thread: ::Thread.new copied the FIRST scheduling
            # caller's fiber storage into this thread at creation (design, verified fact 7), and
            # without this clear every later caller's handler ran underneath it -- caller B's
            # #on_settle tagged with caller A's trace id (review round 2's R2-1). The construction
            # floor; boundary 2 is #fire's ensure.
            clear_fiber_storage
            guarded { run }
          end
        end

        def wake
          @wake.push(:recompute)
        rescue ::ClosedQueueError
          nil
        end

        # P8-22 for the timer thread: a callback that raises -- a Hooks.notify re-raise out of a
        # caller's #on_settle handler on a delay future is the reachable case -- is reported and
        # the thread lives. `on_error` is the pool's contained diagnostic, total by construction,
        # and #fire and #shut_down call it with the entry's snapshot still installed, so the
        # diagnostic carries the delay caller's correlation.
        def guarded
          yield
        rescue ::Exception => error # rubocop:disable Lint/RescueException -- the timer thread never dies; see the class comment
          @on_error.call(error)
          nil
        end

        # Park against the nearest deadline, wake on a push or on that deadline, fire what is
        # due, repeat; exit when the wake queue is closed. `remaining` is nil with nothing
        # scheduled, which is an indefinite pop that a #stop still wakes at once.
        def run
          loop do
            remaining = @mutex.synchronize { next_wait }
            @wake.pop(timeout: remaining)
            break if @wake.closed?

            take_due.each { |entry| fire(entry) }
          end
        end

        # The timer thread's hop (ASYNC-8): the entry's captured context installed for the
        # callback's duration and the thread's prior context restored after it, through 5b's
        # Diagnostics.with exactly as Pool#run does it, with the net INSIDE the install (review
        # round 3's R3-1): `on_error` is the pool's defect diagnostic, the one log event emitted
        # on the delay caller's behalf after the hop, and it folds the caller's `trace.id` only
        # while the snapshot is still installed -- a net around `.with` reported after the
        # restore, on a thread whose own context is empty by construction. `.with`'s own frame
        # cannot raise over a `.capture` snapshot, so the thread's survival is still the body's
        # net. Then P8-20's boundary 2 of 2, not redundant with the thread-start clear: `.with`
        # restores only (prior.keys | snapshot.keys), so a key the HANDLER itself writes is in
        # neither set and would be visible to every later handler on this thread (measured:
        # {written_by_handler: "LEAK"} on the next delay's callback). After the thread-start clear
        # the prior map is provably empty, so re-running the clear IS "restore prior".
        def fire(entry)
          Dexpace::Instrumentation::Diagnostics.with(entry.snapshot) do
            guarded { entry.on_fire.call }
          end
        ensure
          clear_fiber_storage
        end

        # The shutdown outcome, on whichever thread stopped the timer -- the closer's, a worker's
        # whose task closed its own pool, the timer's own when a delay handler did (P8-76), or
        # the scheduling caller's for an entry refused after #stop -- under the same install and
        # restore (ASYNC-9: that thread's prior context is saved and put back), the net inside it
        # for the same reason as #fire's, and with no clear after: a caller's thread is not this
        # timer's to empty, and a worker's or the timer's own is cleared by its own boundary-2
        # ensure once the enclosing task or callback returns.
        def shut_down(entry)
          Dexpace::Instrumentation::Diagnostics.with(entry.snapshot) do
            guarded { entry.on_shutdown.call }
          end
        end

        # Per key, through Fiber[]= alone, never Fiber#storage= (which warns on every call on
        # every supported Ruby); Pool#clear_fiber_storage's spelling, for the same reasons. On the
        # 3.2 floor the write retains the key with a nil value (P5-72), which Fiber[] and
        # Diagnostics.capture both read as absent.
        def clear_fiber_storage
          storage = ::Fiber.current.storage #: untyped
          storage&.each_key { |key| ::Fiber[key] = nil }
          nil
        end

        # Under the mutex: seconds until the nearest deadline, floored at zero, or nil.
        def next_wait
          deadline = @entries.first&.deadline
          return nil if deadline.nil?

          [deadline - @clock.monotonic, 0.0].max
        end

        # Under the mutex: the entries whose deadline has passed, removed from the list in
        # deadline order (the list is kept sorted, and partition preserves it).
        def take_due
          @mutex.synchronize do
            now = @clock.monotonic
            ready, keep = @entries.partition { |entry| entry.deadline <= now }
            @entries = keep
            ready
          end
        end
      end
      private_constant :Timer
    end
  end
end
