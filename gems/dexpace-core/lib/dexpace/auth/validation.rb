# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Auth
    # AUTH-9's non-blank check, which phase 1 ships no helper for. Dexpace::Model.required!
    # raises "<name> is required" only when the value is nil -- that is SEAM-29's one message
    # form for a MISSING field and HTTP-4's rule, and it is deliberately not a blank check. So a
    # nil field still goes through Model.required! and still reads "<name> is required", while
    # a present-but-blank field reads "<name> must not be blank": the two forms name two
    # different mistakes and do not overlap (6c's P6-6). AUTH-14's laxer non-EMPTY rule for a
    # Basic credential is a third check and lives at BasicHandler/DigestHandler, never here.
    #
    # The argument order is Model.required!'s, (name, value), so the two helpers read the same
    # way at every call site; the plan's fence had them the other way round.
    #
    # Not public API: a private_constant reachable by its bare name from any `module Dexpace;
    # module Auth` body, and from nowhere else.
    module Validation
      extend self

      # @param name [String] the field, for the message
      # @param value [Object] the candidate
      # @return [String] the value, unchanged
      # @raise [Dexpace::InvalidArgumentError] when nil, not a String, or blank after strip
      def non_blank!(name, value)
        text = Model.required!(name, value)
        raise InvalidArgumentError, "#{name} must be a String" unless text.is_a?(::String)
        raise InvalidArgumentError, "#{name} must not be blank" if text.strip.empty?

        text
      end
    end
    private_constant :Validation
  end
end
