# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"
require_relative "invalid_argument_error"
require_relative "../http/response"
require_relative "../retryability"

module Dexpace
  # XCUT-4's branch (a): a protocol error carries a fully-received response -- status, headers and
  # a body already buffered to RECOV-16's bound -- and is a StandardError, so a caller is never
  # forced to treat a 404 as an I/O failure. Branch (b), Dexpace::TransportError < ::IOError,
  # carries no response and is phase 8's; both are flat under Dexpace:: because the taxonomy is
  # repository-wide, and both include Dexpace::Error and therefore carry the suppressed trail.
  #
  # One class carrying #status, and no per-status subclass tree (P4-20): XCUT-4 requires exactly
  # two top-level branches and describes no third level, XCUT-7 decides retry eligibility from a
  # configured status set and never from a class, and a caller distinguishes a 404 from a 429 by
  # reading #status -- the same Dexpace::Status phase 1 made comparable. A generated SDK that
  # wants UserNotFoundError passes its own `factory:` to the error-mapping step rather than
  # subclassing this.
  #
  # The message names the status code and its canonical name and never the body: a message is
  # what lands in a log by default, an error body is the payload most likely to carry a token or
  # a customer identifier, and OBS-11..OBS-19's redaction is phase 5's. #response is how a caller
  # who wants the body reads it (the plan's open question 5).
  #
  # #retryable_by_status? is XCUT-5's baked flag (RETRY-3), computed ONCE at construction from
  # the SINGLE shared status classifier -- phase 5a's Dexpace::Retryability, which phase 4b
  # could not build and phase 6a reads rather than rebuilds (its Task 6). It is deliberately
  # NOT named #retryable?, the open capability XCUT-6's throwable query looks for (P6-10): a
  # ProtocolError answering that query would let the baked set override the CONFIGURED set
  # RETRY-37 makes authoritative whenever the error is wrapped in another -- including a set
  # that deliberately narrows -- so the two questions carry two names, design §6.1's own, and
  # the retry drivers consult Resilience::Policy.retry_eligible?(status, set:) and never this.
  class ProtocolError < ::StandardError
    include Dexpace::Error

    # @return [Dexpace::Response] the fully-received response, its body already buffered
    attr_reader :response

    # @return [Dexpace::Status] the response's status, for a caller that branches on it
    attr_reader :status

    # XCUT-8's factory: the matching typed exception for an error status, and an argument error
    # -- never a fabricated "successful exception" -- for a 1xx, 2xx or 3xx.
    #
    # @param response [Dexpace::Response]
    # @return [Dexpace::ProtocolError]
    # @raise [Dexpace::InvalidArgumentError] when the status is not in 400..599
    def self.for(response)
      error = for_or_nil(response)
      return error unless error.nil?

      raise InvalidArgumentError,
            "status #{response.status.code} is not an error status; only 400..599 map to a " \
            "ProtocolError (XCUT-8)"
    end

    # XCUT-8's sanctioned convenience form: nil for a non-error status. It is the shape the
    # error-mapping step needs, and the shape whose own status test RECOV-15 already performs.
    #
    # @param response [Dexpace::Response]
    # @return [Dexpace::ProtocolError, nil]
    def self.for_or_nil(response)
      unless response.is_a?(Response)
        raise InvalidArgumentError, "response must be a Dexpace::Response"
      end

      response.status.error? ? new(response) : nil
    end

    # @param response [Dexpace::Response] the fully-received response
    # @raise [Dexpace::InvalidArgumentError] when it is not a Dexpace::Response
    def initialize(response)
      unless response.is_a?(Response)
        raise InvalidArgumentError, "response must be a Dexpace::Response"
      end

      @response = response
      @status = response.status
      @retryable_by_status = Retryability.retryable_status?(@status)
      super(describe(@status))
    end

    # XCUT-5 / RETRY-3: whether the status is one the built-in classifier calls retryable,
    # baked at construction and never per-subclass -- a queryable property of the error, and not
    # what the retry step consults (XCUT-5's closing NOTE; see the class comment).
    #
    # @return [Boolean]
    def retryable_by_status?
      @retryable_by_status
    end

    private

    def describe(status)
      name = status.canonical_name
      name.nil? ? "HTTP #{status.code}" : "HTTP #{status.code} #{name}"
    end
  end
end
