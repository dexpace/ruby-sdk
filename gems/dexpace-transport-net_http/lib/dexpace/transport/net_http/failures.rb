# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module NetHTTP
      # TRANSPORT-3, TRANSPORT-4 and TRANSPORT-20 in one function, and P6-4's obligation read
      # literally: "wrap, and default to retryable, not wrap and get the classification right by
      # hand". The wrap is a CATCH-ALL, never a lookup against an enumerated list -- a list has
      # exactly one failure mode and it is the bad one: a family nobody thought of escapes
      # unwrapped and classifies NOT retryable through RETRY-2's capability query, which is the
      # blind spot P6-4 names. The families this adapter actually meets are documented here rather
      # than branched on: Net::OpenTimeout, Net::ReadTimeout and Net::WriteTimeout (Timeout::Error
      # < RuntimeError), SocketError (which covers Socket::ResolutionError where it exists),
      # Errno::* through SystemCallError, OpenSSL::SSL::SSLError, EOFError, IOError,
      # Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError and Zlib::Error -- none of which but
      # EOFError and IOError is an ::IOError, and those two still wrap, because phase 3a's
      # Dexpace::EndOfStreamError is a Dexpace::Error and takes the pass-through clause instead.
      # A private_constant of NetHTTP.
      module Failures
        extend self

        # The error to actually raise for whatever escaped the native dispatch. It RETURNS the
        # error and never assigns `#cause`: Ruby populates `#cause` from `$!` at the raise, so a
        # caller raising the result from inside its own `rescue` gets the original as the cause
        # for free, and a caller carrying a failure across a thread boundary passes it explicitly.
        #
        # @param error [Exception] whatever escaped the native dispatch
        # @param phase [Symbol] :connect, :write, :read or :close, for TransportError#phase
        # @param cancellation [Dexpace::Cancellation] the token this call was given
        # @return [Exception] a Dexpace::CancelledError when the token is cancelled, the error
        #   itself when it is already a Dexpace::Error, and a retryable Dexpace::TransportError
        #   otherwise
        def wrap(error, phase:, cancellation:)
          # TRANSPORT-3: ask the TOKEN first, never the exception. A cancel delivered by closing
          # the socket and a peer reset arrive as the SAME IOError with the SAME message, so
          # discrimination by class or by message cannot work at all.
          return ::Dexpace::CancelledError.new(cancellation.reason) if cancellation.cancelled?
          # Never re-wrap what is already ours: double-wrapping a stream-contract violation or a
          # caller's own InvalidArgumentError into an always-retryable transport failure would
          # make RETRY-2 re-send on a caller's own bug.
          return error if own?(error)

          # TRANSPORT-4 and TRANSPORT-20: retryable, and the token is never written here, so a
          # read timeout leaves the cancellation flag exactly as it found it.
          ::Dexpace::TransportError.new(error.message, phase: phase)
        end

        private

        def own?(error)
          error.is_a?(::Dexpace::Error)
        end
      end

      private_constant :Failures
    end
  end
end
