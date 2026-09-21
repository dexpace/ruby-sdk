# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # TRANSPORT-3, TRANSPORT-4 and TRANSPORT-20 in one function, and P6-4's obligation read
      # literally: "wrap, and default to retryable, not wrap and get the classification right by
      # hand". The wrap is a CATCH-ALL, never a lookup against an enumerated list -- a list has
      # exactly one failure mode and it is the bad one: a family nobody thought of escapes
      # unwrapped and classifies NOT retryable through RETRY-2's capability query. The families
      # this adapter actually meets are documented here rather than branched on: Async::TimeoutError
      # (a StandardError, the deadline), Errno::* through SystemCallError, SocketError (which
      # covers Socket::ResolutionError where it exists), OpenSSL::SSL::SSLError, EOFError (a stale
      # keep-alive connection, or a body shorter than its Content-Length), IOError (a connection
      # retired or closed under a read), Protocol::HTTP::Error and everything beneath it --
      # RefusedError, RemoteError, Protocol::HTTP1::BadRequest, Protocol::HTTP2::StreamError --
      # and the NoMethodError a read on a retired connection raises. Not one of them but EOFError
      # and IOError is an ::IOError (the design's verified fact 11), which is what makes
      # Dexpace::TransportError the only thing that lets RETRY-2 see any of them as retryable.
      # Async::Cancel never reaches here: it is not a StandardError, and every caller of #wrap is
      # a `rescue ::StandardError` arm. A private_constant of AsyncHTTP.
      module Errors
        extend self

        # The error to settle the future with for whatever escaped the native dispatch.
        #
        # @param error [Exception] whatever escaped
        # @param phase [Symbol] :connect, :write, :read or :close, for TransportError#phase
        # @param cancellation [Dexpace::Cancellation] the token this call was given
        # @return [Exception] a Dexpace::CancelledError when the token is cancelled (the caller
        #   settles it through Completer#request_cancel), the error itself when it is already a
        #   Dexpace::Error, and a retryable Dexpace::TransportError carrying the original as
        #   `#cause` otherwise
        def wrap(error, phase:, cancellation:)
          # TRANSPORT-3: ask the TOKEN first, never the exception. A cancel delivered by retiring
          # the connection and a peer reset arrive as the SAME IOError with the SAME message, so
          # discrimination by class or by message cannot work at all.
          return ::Dexpace::CancelledError.new(cancellation.reason) if cancellation.cancelled?
          # Never re-wrap what is already ours: double-wrapping a stream-contract violation or a
          # caller's own InvalidArgumentError into an always-retryable transport failure would
          # make RETRY-2 re-send on a caller's own bug.
          return error if own?(error)

          # TRANSPORT-4 and TRANSPORT-20: retryable, and the token is never written here, so a
          # deadline leaves the cancellation flag exactly as it found it.
          with_cause(::Dexpace::TransportError.new(error.message, phase: phase), error)
        end

        # Settles the pivot from whatever escaped: a cancelled token settles a CANCELLATION
        # through Completer#request_cancel -- the one settlement Future#cancelled? reads as true
        # (ASYNC-6) -- and everything else a failure through Completer#fail, wrapped as #wrap
        # wraps it. The one place on this adapter a failure meets the pivot.
        #
        # @param completer [Dexpace::Async::Completer]
        # @param error [Exception] whatever escaped
        # @param phase [Symbol] as for #wrap
        # @param cancellation [Dexpace::Cancellation] as for #wrap
        # @return [Boolean] whether this settlement won the race
        def settle(completer, error, phase:, cancellation:)
          wrapped = wrap(error, phase: phase, cancellation: cancellation)
          if wrapped.is_a?(::Dexpace::CancelledError)
            completer.request_cancel(wrapped.reason)
          else
            completer.fail(wrapped)
          end
        end

        # A body read that failed after the head arrived is phase 3a's contract, never the
        # transport family (P3-3: StreamError is a sibling of TransportError, not a subclass): the
        # response existed, so RETRY-2 has nothing to re-send. The token still comes first, because
        # the cancellation watcher closes the native body from inside the reactor and the blocked
        # read wakes with a bare IOError.
        #
        # @param error [Exception] what `Protocol::HTTP::Body::Readable#read` raised
        # @param cancellation [Dexpace::Cancellation] the token the response was obtained under
        # @return [Exception] a Dexpace::CancelledError, the error itself when it is already a
        #   Dexpace::Error, or a Dexpace::StreamError carrying the original as `#cause`
        def classify_read(error, cancellation:)
          return ::Dexpace::CancelledError.new(cancellation.reason) if cancellation.cancelled?
          return error if own?(error)

          with_cause(::Dexpace::StreamError.new("the response body failed mid-stream: " \
                                                "#{error.class}: #{error.message}"), error,)
        end

        private

        # `#cause` is set by raising inside a rescue of the original, because on the async path the
        # wrapped error is handed to Completer#fail rather than raised from inside a `rescue` where
        # Ruby would attach it for free (pipeline/7ce4431d's discipline, from the other side: an
        # error CARRIED is never raised bare). Exception.new takes no `cause:` keyword.
        def with_cause(wrapped, original)
          raise wrapped, cause: original
        rescue ::Dexpace::TransportError, ::Dexpace::StreamError => error
          error
        end

        # Dexpace::Error is a module, so an `is_a?` on it in the caller would narrow the local to
        # the module's type and lose `Exception` for Steep; the predicate keeps the type whole.
        def own?(error)
          error.is_a?(::Dexpace::Error)
        end
      end

      private_constant :Errors
    end
  end
end
