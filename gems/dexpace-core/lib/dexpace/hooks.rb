# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Running a list of caller-supplied callbacks, in one place, once.
  #
  # Three sites take the same shape -- Cancellation::Source#cancel, Async::Completer#settle and
  # Async::Completer#request_cancel -- and each publishes state under its mutex and then notifies
  # outside it. Written as a bare `hooks.each { |hook| hook.call(...) }` at each site, ONE raising
  # handler drops every later-registered handler and propagates out to whoever published the
  # state. That is the "a second waiter on one token blocks forever" SEAM-18 failure arriving from
  # the write side: the second waiter's handler is simply never called. Verified on 3.2.11, 3.4.10
  # and 4.0.6.
  #
  # So every hook runs, whatever an earlier one did, and the FIRST failure is re-raised once the
  # whole list has run. Re-raised rather than dropped, because phase 2 has neither disposal route
  # design §3.7 names -- Dexpace::Error#suppressed is phase 4b's (Task 1) and the
  # http.instrumentation.* diagnostic is phase 5's (§8.1) -- and a handler that raises into a void
  # is a bug nothing reports. Re-raising is safe here in a way it is not at the naive site: the
  # state is already published and every other handler has already run, so the raise can no longer
  # leave a token uncancelled or a future unsettled. The failures after the first are dropped until
  # #suppressed exists to carry them; phase 4b, Task 2 attaches them.
  #
  # Only StandardError is collected. A ScriptError, a NoMemoryError or a SignalException raised by
  # a handler is not a handler bug to be gathered up and re-raised later.
  module Hooks
    # @param hooks [Array<#call>] the list the caller already stole from under its own lock
    # @param argument [Object] the single argument every hook is called with
    # @return [nil]
    def self.notify(hooks, argument)
      failure = nil #: StandardError?
      hooks.each do |hook|
        hook.call(argument)
      rescue ::StandardError => error
        failure ||= error
      end
      raise failure if failure

      nil
    end
  end

  # Not public API: it is a shape three internal call sites share, not a service core offers. A
  # private_constant is still reachable by the unqualified name from anywhere lexically inside
  # `module Dexpace`, which is where all three call sites are -- verified on 3.2.11, 3.4.10 and
  # 4.0.6 -- and unreachable as `Dexpace::Hooks` from outside.
  private_constant :Hooks
end
