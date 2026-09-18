# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "scheme"
require_relative "requirement"

module Dexpace
  module Auth
    # AUTH-3: a non-empty ordered list of requirements in caller preference order. Immutable in
    # and immutable out: the list is copied and frozen once at construction and #requirements
    # returns that same frozen reference at every call (HTTP-5's pattern, applied for the same
    # reason it is applied to every other model collection). A Requirement is itself deeply
    # frozen, so Model.own keeps each element's identity and freezes only the new list.
    class Descriptor < ::Data.define(:requirements)
      include Model

      private_class_method :new

      # The validating factory; keyword-shaped so Model#with can route a derivation through it.
      #
      # @param requirements [Array<Requirement>] at least one
      # @return [Descriptor]
      # @raise [Dexpace::InvalidArgumentError] on an empty list, or on an element that is not a
      #   Requirement
      def self.build(requirements:)
        new(requirements: requirements)
      end

      def initialize(requirements:)
        list = Model.required!("requirements", requirements)
        raise InvalidArgumentError, "requirements must be an Array" unless list.is_a?(::Array)
        raise InvalidArgumentError, "requirements must be non-empty (AUTH-3)" if list.empty?
        unless list.all?(Requirement)
          raise InvalidArgumentError, "every requirement must be a Dexpace::Auth::Requirement"
        end

        super(requirements: Model.own(list))
      end

      # AUTH-3: true iff any requirement's scheme is the NO_AUTH sentinel.
      #
      # @return [Boolean]
      def allows_anonymous?
        requirements.any? { |requirement| requirement.scheme == Scheme::NO_AUTH }
      end
    end
  end
end
