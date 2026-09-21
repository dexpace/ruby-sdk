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
      # The mutex is held across a list insert, a list delete, a `first` read, the stop flag
      # and the lazy thread creation -- never across #pop(timeout:), a callback or a Completer
      # settle (design, "Thread-safety proof obligations"): Thread::Mutex ownership is per fiber
      # and non-reentrant, so a lock held across a suspension point deadlocks two fibers of one
      # thread. The wait is computed inside the lock and performed outside it.
      class Timer
        # One scheduled deadline and its two outcomes. Crosses the timer thread's boundary:
        # frozen Data, every member immutable by construction (concurrency-and-async/2c743901).
        Entry = ::Data.define(:deadline, :on_fire, :on_shutdown)
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
        # @return [Object] an opaque handle for #cancel
        def schedule(delay, on_fire:, on_shutdown:)
          entry = Entry.new(deadline: @clock.monotonic + delay, on_fire: on_fire,
                            on_shutdown: on_shutdown,)
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
            guarded { entry.on_shutdown.call }
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
        def stop(timeout)
          thread, leftover = @mutex.synchronize do
            @stopped = true
            taken = @entries
            @entries = []
            [@thread, taken]
          end
          @wake.close
          thread&.join(timeout)
          leftover.each { |entry| guarded { entry.on_shutdown.call } }
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
        # the thread lives. `on_error` is the pool's contained diagnostic, total by construction.
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

            take_due.each { |entry| guarded { entry.on_fire.call } }
          end
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
