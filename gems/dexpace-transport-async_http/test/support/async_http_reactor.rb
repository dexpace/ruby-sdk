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

  # @param server [#close] the fixture to close before the reactor drains
  # @yield [Async::Task] the reactor's root task
  def reactor_over(server)
    Sync do |task|
      yield task
    ensure
      server.close
    end
  end

  # After a settlement that delivered no response, the exchange task and its transient watcher
  # are both gone from the reactor: a turn or two for them to finish, then no non-transient child
  # remains and no child is a watcher. The pool's own transient gardener is the one child that
  # legitimately stays for the client's life, which is why the watcher is found by its
  # annotation rather than by counting. The watcher's release is what keeps a long-lived reactor
  # from accumulating one parked task per failed exchange, and this is what turns its absence red.
  #
  # @param task [Async::Task] the task the exchange was spawned under
  def assert_exchange_released(task)
    watcher = Dexpace::Transport::AsyncHTTP.const_get(:Exchange, false)::WATCHER_ANNOTATION
    RELEASE_TURNS.times do
      task.yield
      children = Array(task.children)
      return if children.all?(&:transient?) && children.none? { |c| c.annotation == watcher }
    end

    flunk("the exchange task or its watcher outlived the settlement by #{RELEASE_TURNS} turns")
  end
end
