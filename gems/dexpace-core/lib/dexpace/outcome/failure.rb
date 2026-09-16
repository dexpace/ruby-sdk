# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../outcome"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Outcome
    # RECOV-1's Failure variant: a throwable is in hand and no response is.
    #
    # Phase 1's construction rule taken whole, and one check of its own: the error IS an
    # Exception. Nothing else in the model would catch a Failure carrying a String, and RECOV-10
    # would then `raise` it into a TypeError at the one point the caller is furthest from the
    # cause. Any Exception is accepted, not only a StandardError: the orchestrator never builds a
    # Failure for the fatal family, but a caller's recovery step may return one.
    class Failure < Data.define(:error)
      include Model
      include Outcome

      private_class_method :new

      # The validating factory, and the only way to build one.
      #
      # @param error [Exception]
      # @return [Dexpace::Outcome::Failure]
      # @raise [Dexpace::InvalidArgumentError] when the error is nil or not an Exception
      def self.build(error:)
        new(error: error)
      end

      def initialize(error:)
        Model.required!("error", error)
        raise InvalidArgumentError, "error must be an Exception" unless error.is_a?(::Exception)

        super
      end

      # @return [false]
      def success? = false

      # @return [true]
      def failure? = true

      # @return [nil]
      def response_or_nil = nil

      # RECOV-1's "error-or-null", and the requirement's own nil (P4-21).
      #
      # @return [Exception]
      def error_or_nil = error

      # RECOV-1's fold: exactly one branch, invoked at most once per call, and both branches
      # required on both variants (see Success#fold).
      #
      # @param on_success [#call] not called on a Failure
      # @param on_failure [#call] receives the error
      # @return [Object] what `on_failure` returned
      # @raise [Dexpace::InvalidArgumentError] when either branch is nil
      def fold(on_success:, on_failure:)
        Model.required!("on_success", on_success)
        Model.required!("on_failure", on_failure).call(error)
      end
    end
  end
end
