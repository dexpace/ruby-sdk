# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace/model"
require "dexpace/error/invalid_argument_error"

module Dexpace
  module Conformance
    # One conformance check: the requirement IDs it exercises -- a waiver matches by these, never
    # by #name -- a human name, and a callable body taking one subject (a TransportCase for the
    # transport suite; phase 9 adds suites whose subject is not a transport, which is why the body
    # is typed `^(untyped) -> void` and not against a named interface).
    #
    # Public API crossing into a consumer's own suite, so it follows the phase-1 construction
    # pattern: `.new` private, a validating keyword `.build`, `Model.required!`'s one message form
    # (SEAM-29), the ids copied through `Model.own` so a caller's later mutation cannot reach them,
    # and `#with` through `.build` on every interpreter (Model#with).
    class Assertion < Data.define(:ids, :name, :body)
      include Model

      private_class_method :new

      # The validating factory every construction path goes through.
      #
      # @param ids [Enumerable<String>] the requirement IDs this assertion exercises, non-empty
      # @param name [String] a human name, used for the generated test method's name
      # @param body [#call] the check, taking one subject
      # @return [Assertion] frozen
      # @raise [Dexpace::InvalidArgumentError] naming the member, on any invalid value
      def self.build(ids:, name:, body:)
        new(ids: ids, name: name, body: body)
      end

      def initialize(ids:, name:, body:)
        required = Model.required!("ids", ids).to_a
        unless !required.empty? && required.all?(::String)
          raise InvalidArgumentError, "ids must be a non-empty collection of requirement-ID Strings"
        end
        raise InvalidArgumentError, "body must respond to #call" unless
          Model.required!("body", body).respond_to?(:call)

        super(ids: Model.own(required), name: Model.frozen_string(Model.required!("name", name)),
              body: body,)
      end

      # Runs the check against one subject, returning whatever the body returns; the protocol's
      # signal is what it RAISES -- nothing, a Failure or a Vacuous -- and TransportSuite.run
      # maps that onto a Result.
      #
      # @param subject [Object] what the suite hands each assertion
      # @return [Object] the body's return value, of no significance to the protocol
      def call(subject)
        body.call(subject)
      end
    end
  end
end
