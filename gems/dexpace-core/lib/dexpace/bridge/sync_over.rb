# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../async/future"
require_relative "../closeable"
require_relative "../error/seam_error"

module Dexpace
  module Bridge
    # An asynchronous transport presented as a blocking one.
    #
    # SEAM-18's three clauses. *Unwrap the async-wrapper exception*: this port never wraps --
    # Completer#fail stores the error and Future#value re-raises that object -- so the clause holds
    # structurally and the test asserts object identity rather than an equal message. *Honour
    # interruption*: the wait takes the cancellation token, and on cancellation it cancels the
    # in-flight future and raises Dexpace::CancelledError. "Restore the interrupt flag" is vacuous
    # for exactly the reason ASYNC-4 is (design §10.5): a port that never delivers an interrupt
    # cannot leave a stale one set. "Surface an interrupted-I/O error" is read as a typed
    # cancellation error rather than an IOError, because XCUT-4's I/O family is for transport
    # failures and a cancellation is not one (deviation P2-4). *Options are threaded*: they are
    # passed through unchanged, and a test asserts the exact object arrives.
    #
    # Closeable and not owning, for the same reason AsyncOver is: the wrapped transport is the
    # caller's (SEAM-14, XCUT-22).
    class SyncOver
      include Dexpace::Closeable

      def initialize(transport)
        @transport = transport
        initialize_closeable(owned: false)
      end

      # The blocking send: dispatches, then waits on the future under the caller's token.
      def call(request, options, cancellation)
        future = @transport.call(request, options, cancellation)
        unless future.is_a?(Dexpace::Async::Future)
          raise Dexpace::SeamError,
                "an async transport must return a Dexpace::Async::Future, got #{future.class}"
        end

        future.value(cancellation: cancellation)
      end
    end
  end
end
