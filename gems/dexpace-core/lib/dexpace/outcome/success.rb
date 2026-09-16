# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../outcome"
require_relative "../http/response"

module Dexpace
  module Outcome
    # RECOV-1's Success variant: a response is in hand.
    #
    # Phase 1's construction rule taken whole: `.build` is the `new` wrapper and the validation
    # lives in this type's own `initialize`, so `Data#with` cannot route around it on any
    # interpreter, and Model#with routes through `.build` besides. A Success is a frozen Data
    # over one member, so two Successes over one response are equal; no shareability claim is
    # made, because the response holds a body holding an IO.
    class Success < Data.define(:response)
      include Model
      include Outcome

      private_class_method :new

      # The validating factory, and the only way to build one.
      #
      # @param response [Dexpace::Response]
      # @return [Dexpace::Outcome::Success]
      # @raise [Dexpace::InvalidArgumentError] when the response is nil or not a Response
      def self.build(response:)
        new(response: response)
      end

      def initialize(response:)
        Model.required!("response", response)
        unless response.is_a?(Response)
          raise InvalidArgumentError, "response must be a Dexpace::Response"
        end

        super
      end

      # @return [true]
      def success? = true

      # @return [false]
      def failure? = false

      # RECOV-1's "response-or-null", and the requirement's own nil (P4-21): core never calls it,
      # #fold and the predicates are the non-nil routes.
      #
      # @return [Dexpace::Response]
      def response_or_nil = response

      # @return [nil]
      def error_or_nil = nil

      # RECOV-1's fold: exactly one branch, invoked at most once per call. There is no loop and
      # no retry, so the property is structural rather than defended. Both branches are required
      # on both variants, so a caller who passes a nil branch learns it here rather than on the
      # first outcome of the other kind.
      #
      # @param on_success [#call] receives the response
      # @param on_failure [#call] not called on a Success
      # @return [Object] what `on_success` returned
      # @raise [Dexpace::InvalidArgumentError] when either branch is nil
      def fold(on_success:, on_failure:)
        Model.required!("on_failure", on_failure)
        Model.required!("on_success", on_success).call(response)
      end
    end
  end
end
