# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # Raised from INSIDE an assertion body once it has established that the requirement's own
    # antecedent is absent for the subject under test -- never a skip decided from a list outside
    # it, so vacuity is a measurement and not a claim. A class of its own rather than a Failure,
    # because design §12's MUST-level summary counts requirements that "hold vacuously" apart from
    # ones that passed, and a Report that folded the two together would be the mechanism by which
    # that count stops being true. Like Failure, a test result and not a Dexpace::Error (P8-8).
    class Vacuous < ::StandardError
      # @return [String] why the antecedent is absent on this subject
      attr_reader :reason

      # @param reason [String] why the antecedent is absent, which is also the message
      def initialize(reason)
        @reason = reason
        super
      end
    end
  end
end
