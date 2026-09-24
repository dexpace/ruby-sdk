# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "failure"

module Dexpace
  module Conformance
    # The one assertion primitive every phase-9 suite body uses: a condition, the sentence that
    # says what went wrong, the two values compared, and the requirement IDs the comparison is
    # evidence for. Its own file because one public constant per file is this repository's rule
    # and phase 9's own code sits inside the NFR-3 assertion phase 9 ships.
    module Check
      extend self

      # @param condition [Object] truthy when the property holds
      # @param message [String] what went wrong, in words
      # @param expected [Object] what the assertion expected
      # @param actual [Object] what it found
      # @param ids [Array<String>] the requirement IDs this comparison is evidence for
      # @return [nil]
      # @raise [Failure] when `condition` is falsey
      def that(condition, message, expected:, actual:, ids:)
        return nil if condition

        raise Failure.new(message, expected: expected, actual: actual, requirement_ids: ids)
      end
    end
  end
end
