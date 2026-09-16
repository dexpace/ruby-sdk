# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "suppressible"

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
  # whole list has run, carrying every later failure on its suppressed trail -- the first of
  # design §3.7's two disposal routes, which phase 2 postponed and phase 4b (Task 2) supplied. The
  # carrier is Dexpace::Suppressible and not Dexpace::Error: a handler's failure is a caller's
  # exception, so Dexpace.attach_suppressed extends it (P4-12). The second route, the
  # http.instrumentation.* diagnostic, is phase 5's (§8.1) and may report each attached failure;
  # it does not replace the trail. Re-raising is safe here in a way it is not at the naive site:
  # the state is already published and every other handler has already run, so the raise can no
  # longer leave a token uncancelled or a future unsettled.
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
        failure ? Dexpace.attach_suppressed(failure, error) : (failure = error)
      end
      # `cause: nil`, because this line re-raises an error it has been CARRYING since an earlier
      # iteration rather than one it just rescued: a bare `raise` would hand it the caller's
      # in-flight $! as a #cause whenever a hook list is drained from inside a rescue (verified
      # on 3.2.11, 3.4.10 and 4.0.6). It suppresses an assignment this line would itself make
      # and clears nothing a hook's own `raise` already assigned, so the object surfaced is the
      # same object -- "re-raise as now", exactly.
      raise failure, cause: nil if failure

      nil
    end
  end

  # Not public API: it is a shape three internal call sites share, not a service core offers. A
  # private_constant is still reachable by the unqualified name from anywhere lexically inside
  # `module Dexpace`, which is where all three call sites are -- verified on 3.2.11, 3.4.10 and
  # 4.0.6 -- and unreachable as `Dexpace::Hooks` from outside.
  private_constant :Hooks
end
