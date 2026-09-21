# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace/model"
require "dexpace/error/invalid_argument_error"
require_relative "assertion"

module Dexpace
  module Conformance
    # One assertion's outcome. `status` is one of the five in STATUSES -- never a boolean, because
    # collapsing five outcomes into pass/fail is exactly what makes a vacuous requirement
    # indistinguishable from one nobody ever checked (design §12; 8a's R7). `detail` is the
    # failure's message, the vacuous reason or the error's class and message, and nil on a pass.
    class Result < Data.define(:assertion, :status, :detail)
      include Model

      private_class_method :new

      # The five outcomes: the assertion returned (:passed), raised a Failure (:failed), raised a
      # Vacuous (:vacuous), was suppressed by a named waiver before it ran (:waived), or raised
      # anything else (:error -- never silently a failure).
      STATUSES = %i[passed failed vacuous waived error].freeze

      # The validating factory every construction path goes through.
      #
      # @param assertion [Assertion] the assertion this is the outcome of
      # @param status [Symbol] one of STATUSES
      # @param detail [String, nil] the failure message, reason or error rendering
      # @return [Result] frozen
      # @raise [Dexpace::InvalidArgumentError] on a status outside the five, or a missing assertion
      def self.build(assertion:, status:, detail: nil)
        new(assertion: assertion, status: status, detail: detail)
      end

      def initialize(assertion:, status:, detail: nil)
        unless Model.required!("assertion", assertion).is_a?(Assertion)
          raise InvalidArgumentError, "assertion must be a Dexpace::Conformance::Assertion"
        end
        unless STATUSES.include?(status)
          raise InvalidArgumentError, "status must be one of: #{STATUSES.join(", ")}"
        end

        super
      end
    end
  end
end
