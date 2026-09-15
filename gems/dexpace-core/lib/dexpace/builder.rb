# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/invalid_argument_error"

module Dexpace
  # SEAM-29's shared generic builder contract: `#build` produces the target type, and a generic
  # composition helper can therefore accept any builder without knowing which model it makes.
  #
  # In Ruby the assignability half of that requirement is carried by the RBS interface
  # `Dexpace::_Builder[T]`, which is what a consumer's own `steep check` sees; this module is its
  # runtime half, so a helper can also refuse an object that never opted in.
  module Builder
    # The generic composition helper the requirement exists for.
    def self.build_all(builders)
      builders.map do |builder|
        unless builder.is_a?(Builder)
          raise InvalidArgumentError, "#{builder.class} does not implement the builder contract"
        end

        builder.build
      end
    end

    # Deliberately NotImplementedError, which is a ScriptError and not a StandardError: a builder
    # class that forgot #build is a programmer error and must not be swallowed by an ordinary
    # `rescue`.
    def build
      raise NotImplementedError, "#{self.class} must implement #build (SEAM-29)"
    end
  end
end
