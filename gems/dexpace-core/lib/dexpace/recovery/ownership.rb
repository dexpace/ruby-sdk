# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../recovery"
require_relative "../closeable"
require_relative "../error/outcome_error"
require_relative "../outcome"
require_relative "../outcome/success"
require_relative "../outcome/failure"

module Dexpace
  module Recovery
    # The ONE place RECOV-12's and RECOV-13's ownership asymmetry lives (design §5.2: "one
    # shared helper so the asymmetry lives in one place"). Every step invocation in ResponseChain
    # goes through it, and no other code in the recovery layer closes a response.
    #
    # The name states the asymmetry. On a raise with a Success in hand, the in-hand response is
    # closed BEFORE the throwable is wrapped, any close error is attached to the throwable as
    # suppressed so it never masks the primary, and the raise becomes a Failure (RECOV-12). On a
    # raise with a Failure in hand there is nothing to close, and the raise becomes a Failure. On
    # a normal return the block's value comes back untouched: a step that deliberately returned a
    # different outcome owns releasing what it dropped, and this helper does not (RECOV-13) --
    # RECOV-13's half is the ABSENCE of a close on that path.
    #
    # The close is Dexpace.close_quietly(response, onto: error): a rescue INSIDE the region
    # rather than a bare close, because an exception escaping here would replace the primary and
    # leave it reachable only through #cause (verified on 3.2.11, 3.4.10 and 4.0.6), which is
    # the masking RECOV-12 forbids in its own sentence. That is close_quietly's first disposal
    # route, and this is its first core caller. A NotImplementedError from a body that forgot
    # #release still propagates, exactly as everywhere else.
    #
    # "Exactly once" is Closeable's latch and not bookkeeping: the error-mapping step buffers
    # the body -- which closes the original -- and then raises, so the close here is a second
    # close of an already-closed body and releases nothing.
    #
    # Two exceptions to the conversion, named in order (R6, P4-19): Dexpace::OutcomeError, a
    # defect in the fold's own input, is re-raised by name rather than converted, because
    # NoMatchingPatternError is inside StandardError and converting a core defect into a Failure
    # would let a later recovery step swallow it; and the fatal family outside StandardError is
    # surfaced unchanged, with no close and no trail (RETRY-25). Not public API: a
    # private_constant, asserted at its call sites, with a sig/ mirror so the strict Steep target
    # can type them.
    module Ownership
      # @param outcome [Dexpace::Outcome] the outcome in hand while the block runs
      # @yieldreturn [Dexpace::Outcome] the outcome after the step
      # @return [Dexpace::Outcome] the block's value, or a Failure carrying what it raised
      def self.close_on_throw(outcome)
        yield
      rescue OutcomeError
        raise
      rescue ::StandardError => error
        Dexpace.close_quietly(outcome.response, onto: error) if outcome.is_a?(Outcome::Success)
        Outcome::Failure.build(error: error)
      end
    end
    private_constant :Ownership
  end
end
