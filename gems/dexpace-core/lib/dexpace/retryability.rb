# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/invalid_argument_error"

module Dexpace
  # The built-in retryability classifier: CFG-35's status half, which is XCUT-5's SINGLE shared
  # status classifier. The status set is a hard contract -- 408, 429 and every 5xx except 501 and
  # 505 -- so that exception construction and the retry policy agree: phase 6a computes
  # Dexpace::ProtocolError's baked flag FROM this predicate (its plan, Task 6) and builds no
  # second classifier.
  #
  # A predicate and not an exposed set, deliberately. XCUT-7's CONFIGURABLE retryable-status set
  # -- default {408, 429, 500, 502, 503, 504}, a subset of this classification -- is a different
  # object, phase 6's, enumerable and mutable by configuration; publishing this classification as
  # a second enumerable constant beside it is how the two get confused, which XCUT-5's closing
  # NOTE exists to prevent. The classifier is a rule; the configurable set is data; only the
  # second is a collection.
  #
  # The THROWABLE half of CFG-35 -- "retryable iff it or any throwable in its cause chain is an
  # IO/timeout error" -- ships no method here, not even one returning false (R1): a bare
  # interpreter defines none of SocketError, Timeout::Error or OpenSSL::SSL::SSLError, none of
  # the ones core can name is an IOError while phase 3a's Dexpace::StreamError is, and a wrong
  # answer under NFR-4's lock can only be changed by breaking. Phase 6a's Task 3 supplies it
  # through XCUT-6's capability, over Dexpace.each_cause.
  module Retryability
    extend self

    # Whether the status is one the shared classification calls retryable.
    #
    # @param status [Integer, Dexpace::Status, #code] a status code, or anything answering #code
    # @return [Boolean]
    # @raise [Dexpace::InvalidArgumentError] when the argument is neither
    def retryable_status?(status)
      # The signature types the argument as an Integer or a _RetryableStatus; the probe below is
      # the runtime half of that promise, so it reads the object untyped.
      probe = status #: untyped
      code = probe.respond_to?(:code) ? probe.code : probe
      unless code.is_a?(::Integer)
        raise InvalidArgumentError,
              "status must be an Integer or answer #code with one, got #{probe.class}"
      end

      return true if [408, 429].include?(code)
      return false if [501, 505].include?(code)

      (500..599).cover?(code)
    end
  end
end
