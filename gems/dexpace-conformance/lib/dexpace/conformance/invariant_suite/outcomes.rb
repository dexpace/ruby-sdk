# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../failure"
require_relative "../vacuous"

module Dexpace
  module Conformance
    module InvariantSuite
      # The four ways an assertion in this suite observes what a call DID, shared by every group so
      # the discipline below is written once.
      #
      # **Vacuous and Failure are re-RAISED rather than captured.** Both are ::StandardError
      # descendants (8a), so a bare `rescue ::StandardError` here would turn this suite's OWN
      # vacuity -- a factory the driver did not supply -- into evidence that the subject refused,
      # which is the silent-pass shape design R3 exists to remove.
      #
      # A private_constant of InvariantSuite.
      module Outcomes
        extend self

        # @return [Class, nil] the class of the error the call raised, or nil when it returned
        def raised_class(callable)
          raised_by(callable)&.class
        end

        # @return [StandardError, nil] the error the call raised, or nil when it returned
        def raised_by(callable)
          callable.call
          nil
        rescue Vacuous, Failure
          raise
        rescue ::StandardError => error
          error
        end

        # @return [Boolean] whether the call raised at all
        def refused?(callable)
          !raised_by(callable).nil?
        end

        # The value OR the error, so a clause whose subject is "this must NOT raise" reports
        # :failed rather than :error -- the status for "the subject is non-conformant" rather than
        # for "this assertion is broken".
        #
        # @return [Object] the call's value, or the error it raised
        def outcome_of(callable)
          callable.call
        rescue Vacuous, Failure
          raise
        rescue ::StandardError => error
          error
        end
      end
      private_constant :Outcomes
    end
  end
end
