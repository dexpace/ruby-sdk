# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # The assertion protocol's failure (design §9.3): what an assertion raises instead of returning
    # cleanly, carrying the expected and actual values it compared and the requirement IDs it was
    # checking. A TEST RESULT, not an SDK error -- P8-8 records why this is a ::StandardError that
    # does NOT include Dexpace::Error: phase 1 made that module the root every SDK error includes so
    # a caller can `rescue Dexpace::Error` broadly, and an adapter author's broad rescue around a
    # send must not swallow the assertion that the send was wrong.
    class Failure < ::StandardError
      # @return [Object] what the assertion expected
      attr_reader :expected
      # @return [Object] what it found
      attr_reader :actual
      # @return [Array<String>] the requirement IDs the assertion was checking, frozen
      attr_reader :requirement_ids

      # @param message [String] the failure, in words
      # @param expected [Object] what the assertion expected
      # @param actual [Object] what it found
      # @param requirement_ids [Array<String>] the IDs it was checking
      def initialize(message, expected:, actual:, requirement_ids:)
        @expected = expected
        @actual = actual
        @requirement_ids = requirement_ids.dup.freeze
        super(message)
      end
    end
  end
end
