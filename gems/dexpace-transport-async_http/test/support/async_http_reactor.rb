# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "async"

# A reactor for a test that drives an exchange against a holding fixture (AsyncHTTPHoldingServer,
# AsyncHTTPSilentServer). The fixture is closed INSIDE the block's ensure -- before `Sync` waits
# for the reactor's children -- so an exchange a defective adapter left blocked on the fixture is
# released by the fixture's close and the failed assertion surfaces as a failure, where an ensure
# outside the `Sync` leaves the reactor waiting on that exchange forever. Two of the reviewer's
# mutations (the token hook cancelling the exchange directly; the per-call timeout removed) hung
# the suite rather than failing it until this existed (2026-09-21); the outer ensure a test keeps
# is still the fixture's release on every other path, and both closes are idempotent.
module AsyncHTTPReactor
  # How many reactor turns a finished exchange and its watcher are given to be consumed from the
  # task tree: the cancel a watcher delivers hands control to the exchange first and the watcher
  # is resumed a turn later (measured: two turns on a cancellation, one on a timeout), while a
  # watcher a defect never released stays for good.
  RELEASE_TURNS = 10

  # The io-event selectors this host can run, in a fixed order. `IO::Event::Selector.new` picks
  # io_uring wherever liburing was present at build time and EPoll otherwise, so a developer
  # machine and a hosted CI runner run DIFFERENT selectors under a bare `Sync` -- and they differ
  # on exactly the property TRANSPORT-7's body path rests on: io_uring's poll notices a
  # descriptor closed under a parked fiber and epoll silently drops it. A test that names the
  # selector is what makes that behaviour the same on every host (the CI failure of 2026-09-22 to
  # 2026-09-25, green here on io_uring and red on every runner's EPoll).
  SELECTORS = (%i[URing EPoll KQueue Select] & ::IO::Event::Selector.constants).freeze

  # @param server [#close] the fixture to close before the reactor drains
  # @param selector [Symbol, nil] an entry of SELECTORS, or nil for the host's default
  # @yield [Async::Task] the reactor's root task
  def reactor_over(server, selector: nil)
    body = proc do |task|
      yield task
    ensure
      server.close
    end
    selector.nil? ? Sync(&body) : reactor_on(selector, &body)
  end

  # `Sync` over a named selector: the same shape as `Kernel#Sync` with no reactor running, the
  # selector handed to the reactor instead of chosen by io-event.
  #
  # @param selector [Symbol] an entry of SELECTORS
  # @yield [Async::Task] the reactor's root task
  def reactor_on(selector, &)
    ::Fiber.blocking do
      implementation = ::IO::Event::Selector.const_get(selector)
      reactor = ::Async::Reactor.new(selector: implementation.new(::Fiber.current))
      begin
        reactor.run(finished: false, &).wait
      ensure
        ::Fiber.set_scheduler(nil)
      end
    end
  end

  # The watcher tasks alive under `task`, found by the adapter's own annotation: one per exchange
  # whose queue is still open -- in flight, or delivered with its body not yet released.
  #
  # @param task [Async::Task] the task the exchange was spawned under
  # @return [Array<Async::Task>]
  def watcher_tasks(task)
    watcher = Dexpace::Transport::AsyncHTTP.const_get(:Exchange, false)::WATCHER_ANNOTATION
    Array(task.children).select { |child| child.annotation == watcher }
  end

  # After a settlement that delivered no response, or after a delivered body's release, the
  # exchange task and its transient watcher are both gone from the reactor: a turn or two for
  # them to finish, then no non-transient child remains and no child is a watcher. The pool's own
  # transient gardener is the one child that legitimately stays for the client's life, which is
  # why the watcher is found by its annotation rather than by counting. The watcher's release is
  # what keeps a long-lived reactor from accumulating one parked task per failed exchange, and
  # this is what turns its absence red.
  #
  # @param task [Async::Task] the task the exchange was spawned under
  def assert_exchange_released(task)
    RELEASE_TURNS.times do
      task.yield
      return if Array(task.children).all?(&:transient?) && watcher_tasks(task).empty?
    end

    flunk("the exchange task or its watcher outlived the settlement by #{RELEASE_TURNS} turns")
  end
end
