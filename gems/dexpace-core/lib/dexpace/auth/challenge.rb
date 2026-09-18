# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Auth
    # AUTH-12: one parsed RFC 7235 challenge -- a lower-cased scheme and a frozen Hash of
    # lower-cased parameter names to verbatim (unquoted, unescaped) String values. A token68
    # value sits under the synthetic key TOKEN68. The folding happens HERE, at construction,
    # rather than in the parser alone, so a challenge a test or a caller builds by hand meets a
    # handler in the same shape a parsed one does (`Challenge.build(scheme: "BASIC")` has the
    # scheme "basic"); the fold is the bare, locale-independent downcase (HTTP-13).
    class Challenge < ::Data.define(:scheme, :params)
      include Model

      private_class_method :new

      # The synthetic parameter key a token68 value is recorded under (AUTH-12).
      TOKEN68 = "token68"

      # The validating factory; #with routes through it.
      #
      # @param scheme [String] the auth-scheme token, in any case
      # @param params [Hash{String => String}] parameter names in any case, values verbatim
      # @return [Challenge]
      def self.build(scheme:, params: {})
        new(scheme: scheme, params: params)
      end

      def initialize(scheme:, params:)
        name = Model.required!("scheme", scheme)
        unless name.is_a?(::String) && !name.strip.empty?
          raise InvalidArgumentError, "scheme must be a non-empty String"
        end
        raise InvalidArgumentError, "params must be a Hash" unless params.is_a?(::Hash)

        super(scheme: name.downcase.freeze, params: Model.own(fold(params)))
      end

      # @return [String, nil] the token68 value, when the challenge carried one
      def token68 = params[TOKEN68]

      private

      # Every key a String folded once; every value a String, verbatim.
      def fold(params)
        params.to_h do |key, value|
          unless key.is_a?(::String) && value.is_a?(::String)
            raise InvalidArgumentError, "challenge params are String names to String values"
          end

          [key.downcase, value]
        end
      end
    end
  end
end
