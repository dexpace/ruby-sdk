# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"
require_relative "invalid_argument_error"

module Dexpace
  # Raised when a value that is not a Dexpace::Outcome reaches a fold that must be exhaustive over
  # the two variants: a recovery step that returned something else, or a response chain whose
  # #apply did. It is a defect in the code that produced the value, not an outcome of the send,
  # and the recovery orchestrator re-raises it by name in the same arm that already re-raises the
  # fatal family (R6, P4-19).
  #
  # A StandardError, deliberately, and named in that arm rather than placed outside StandardError
  # to get past it for free: every SDK failure is a typed StandardError subclass, and borrowing
  # ScriptError's family for its rescue behaviour would make a later `rescue ScriptError` mean two
  # things. The trade is that RECOV-8's "MUST NOT throw under any input" holds over StandardError
  # with this class as a stated exception -- the same trade the port already made for the fatal
  # family, and for the same reason: NoMatchingPatternError is inside StandardError, so the
  # conforming-looking route would convert a core defect into a Failure a recovery step may
  # legitimately turn into a 200, and the caller could not tell.
  #
  # It carries the offending value's CLASS and never the value: an OutcomeError can end up on a
  # suppressed trail, and retaining an arbitrary object there would pin whatever it holds.
  class OutcomeError < ::StandardError
    include Dexpace::Error

    # @return [Module] the class of the value that was not an Outcome
    attr_reader :offending_class

    # @param offending_class [Module] the class of the value that reached the fold
    # @raise [Dexpace::InvalidArgumentError] when it is not a Module
    def initialize(offending_class)
      unless offending_class.is_a?(::Module)
        raise InvalidArgumentError, "offending_class must be a Module"
      end

      @offending_class = offending_class
      super("expected a Dexpace::Outcome from a step, got #{article(offending_class.name)}")
    end

    private

    def article(name)
      name.to_s.match?(/\A[AEIOU]/) ? "an #{name}" : "a #{name}"
    end
  end
end
