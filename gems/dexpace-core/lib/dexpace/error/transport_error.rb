# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # The canonical retryable transport failure (TRANSPORT-20), raised by an adapter for any failure
  # that produced no HTTP response: connection refused, DNS failure, TLS handshake failure, peer
  # reset, a connect, read or write timeout.
  #
  # An ::IOError and never a subclass of Dexpace::StreamError (P3-3): XCUT-4 splits the failures
  # near a transport into exactly two branches -- (a) a stream-contract violation, never retryable
  # by default, and (b) "everything else escaping a transport", always retryable by default -- and
  # a shared ancestor would let `rescue Dexpace::StreamError` catch a transport failure it was never
  # written to expect, or the reverse. The one flag below is P6-4's obligation answered in one
  # place: "wrap, and default to retryable", not ten rescue clauses classifying by hand at the call
  # site. Phase 8's phase-level task, landed by 8a and cited by 8c; verified fact 7 of 8a's design
  # is why it cannot be skipped -- none of `Net::OpenTimeout`, `Net::ReadTimeout`, `SocketError`,
  # `Errno::*`, `OpenSSL::SSL::SSLError`, `Net::HTTPBadResponse` or `Net::HTTPHeaderSyntaxError`
  # is an ::IOError, so a bare one escaping an adapter classifies NOT retryable through RETRY-2's
  # capability query.
  class TransportError < ::IOError
    include Dexpace::Error

    # Where the failure occurred -- :connect, :write, :read or :close -- for diagnostics only.
    # RETRY-2's capability query reads #retryable? alone and never branches on this.
    #
    # @return [Symbol, nil]
    attr_reader :phase

    # @param message [String] the failure, defaulting to a generic one so a bare `raise
    #   Dexpace::TransportError` still reads
    # @param phase [Symbol, nil] where it occurred, for the record and never for a decision
    def initialize(message = "a transport failure occurred", phase: nil)
      @phase = phase
      super(message)
    end

    # RETRY-2's capability query. Always true: XCUT-4 branch (b) is "MUST report itself as
    # always-retryable at the error level", not "retryable when the cause looks retryable", and
    # there is deliberately no keyword that can answer otherwise. The retry budget and RETRY-7's
    # idempotency gate are what bound a resend, never this flag.
    #
    # @return [true]
    def retryable?
      true
    end
  end
end
