# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/invalid_argument_error"

module Dexpace
  module SSE
    # SSE-34's two non-value mapper outcomes, as a type: Dexpace::SSE::SKIP and Dexpace::SSE::DONE
    # are its only two instances. A typed stream's mapper returns a decoded value, or SKIP to drop
    # the event and advance, or DONE to end the iteration cleanly and close the stream (P7-23).
    #
    # The set is closed by construction -- both generated constructors are private, there is no
    # public factory and #with refuses -- so every outcome comparison in the subsystem is an
    # identity test (`equal?`) against one of the two constants, and a decoded model that happens
    # to `==` a sentinel can never be mistaken for one. The send hole phase 1's P8 names stays
    # open and is not closable; it mints an object that is `==` a constant and not `equal?` to
    # it, which the identity dispatch reads as an ordinary value.
    #
    # Dexpace::Outcome::Success and ::Failure are deliberately NOT reused: Success's single member
    # is `response: Dexpace::Response` (phase 4b), and Skip and Done are both *successful* outcomes
    # that differ in what the iterator does next, so Outcome's success/failure surface answers a
    # question this adapter is not asking (P7-23). Nor are 7a's serde sentinels borrowed: naming
    # a Dexpace::Serde constant here would be the serialization dependency SSE-37 forbids.
    #
    # The design named this type `Signal`. Inside `module Dexpace::SSE` a bare `Signal` would
    # resolve to it and no longer to Ruby's ::Signal, the same shadow Dexpace::Method and
    # Dexpace::IO cast on their names, and NFR-4 locks whichever name ships -- so it ships as
    # Sentinel, which shadows nothing (the phase-7b checklist's as-built row).
    class Sentinel < ::Data.define(:name)
      # Data.define generates .[] alongside .new; both are private, because the closed-set claim
      # is structural and .[] alone would reopen it (Pipeline::Stage's P4-32 precedent).
      private_class_method :new, :[]

      # The constant's own name, so a sentinel that reaches a log or a failure message identifies
      # itself instead of printing a Data dump.
      def to_s = "Dexpace::SSE::#{name.to_s.upcase}"

      # The same, so an #inspect in an assertion message or a REPL reads as the constant.
      def inspect = to_s

      # pp.rb gives Data its own #pretty_print over `members` and never consults an #inspect
      # override (6c's P6-72), so `pp Dexpace::SSE::SKIP` needs this third override too.
      def pretty_print(printer) = printer.text(inspect)

      # The closed set has no derivation: a derived sentinel would be neither constant.
      #
      # @raise [Dexpace::InvalidArgumentError] always
      def with(_changes = nil)
        raise InvalidArgumentError,
              "a sentinel cannot be derived; the two outcomes are Dexpace::SSE::SKIP and " \
              "Dexpace::SSE::DONE (SSE-34)"
      end
    end
  end
end
