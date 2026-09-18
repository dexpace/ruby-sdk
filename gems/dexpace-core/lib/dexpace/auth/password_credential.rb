# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Auth
    # AUTH-8, AUTH-14: the username/password pair the Basic and Digest handlers consume. A Data,
    # so two credentials with equal fields are == -- AUTH-8 names no equality rule for this type
    # and Data's generated value equality is the harmless default.
    #
    # No blank check at construction (6c's P6-3): AUTH-9 enumerates exactly three types and this
    # is not one of them, and AUTH-14 fixes a LAXER non-empty rule for Basic that "permits
    # whitespace-only values". So the two fields are only required to be present and Strings
    # here -- HTTP-4's missing-field rule, not AUTH-9's -- and each handler applies AUTH-14's
    # rule at the point it uses the credential, so a blank is refused exactly once, by the rule
    # that governs it.
    #
    # Both fields are redacted in every rendering, the username included. AUTH-8 does not list
    # the username among the non-secret fields it lets remain visible, a Basic username is half
    # of the value that goes on the wire, and phase 5a's review masked the proxy username for
    # the same pair (its checklist, item 24). #pretty_print is overridden for the reason
    # BearerToken states.
    class PasswordCredential < ::Data.define(:username, :password)
      include Model

      private_class_method :new

      # The validating factory; #with routes through it.
      #
      # @param username [String]
      # @param password [String]
      # @return [PasswordCredential]
      def self.build(username:, password:)
        new(username: username, password: password)
      end

      def initialize(username:, password:)
        user = Model.required!("username", username)
        raise InvalidArgumentError, "username must be a String" unless user.is_a?(::String)

        pass = Model.required!("password", password)
        raise InvalidArgumentError, "password must be a String" unless pass.is_a?(::String)

        super(username: Model.frozen_string(user), password: Model.frozen_string(pass))
      end

      # @return [String] both fields redacted
      def to_s = "PasswordCredential(username=#{REDACTED}, password=#{REDACTED})"

      # @return [String] both fields redacted
      def inspect = "#<Dexpace::Auth::PasswordCredential username=#{REDACTED} password=#{REDACTED}>"

      # The rendering `pp` uses; see BearerToken.
      #
      # @param printer [PP]
      # @return [void]
      def pretty_print(printer)
        printer.text(inspect)
      end
    end
  end
end
