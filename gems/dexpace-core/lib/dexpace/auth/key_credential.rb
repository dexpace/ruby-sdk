# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../http/header_name"
require_relative "validation"

module Dexpace
  module Auth
    # AUTH-8, AUTH-9, AUTH-26: a static API key and the header it is stamped into. A plain
    # class, not a Data, and deliberately so: AUTH-8 gives the two key credentials reference
    # identity -- "two instances with identical fields are NOT equal" -- so no ==, eql? or hash
    # is defined and Ruby's identity default is what a caller gets (design §6.3). With no
    # derivation and no value equality there is nothing for Model to add, so .new stays public
    # and validates in place; the instance freezes itself at the end of construction.
    #
    # #prefix and #key_value are the pair KeyStamper is written against, for both key types.
    class KeyCredential
      # @return [String] the header the key is stamped into; "Authorization" by default
      attr_reader :header_name
      # @return [String, nil] what precedes the key, separated by one space (AUTH-26)
      attr_reader :prefix

      # @param api_key [String] non-blank (AUTH-9)
      # @param header_name [String] a valid header name (HTTP-17)
      # @param prefix [String, nil] a non-blank prefix, or nil for none
      def initialize(api_key:, header_name: "Authorization", prefix: nil)
        @api_key = Model.frozen_string(Validation.non_blank!("api_key", api_key))
        @header_name = Model.frozen_string(HeaderName.of(header_name).original)
        @prefix = prefix.nil? ? nil : Model.frozen_string(Validation.non_blank!("prefix", prefix))
        freeze
      end

      # The secret, for the stamper. Never rendered by #to_s, #inspect or pretty-print.
      #
      # @return [String]
      def key_value = @api_key

      # @return [String] the key redacted, the header name and prefix visible
      def to_s
        "KeyCredential(api_key=#{REDACTED}, header_name=#{@header_name.inspect}, " \
          "prefix=#{@prefix.inspect})"
      end

      # @return [String] the key redacted, the header name and prefix visible
      def inspect
        "#<Dexpace::Auth::KeyCredential api_key=#{REDACTED} header_name=#{@header_name.inspect} " \
          "prefix=#{@prefix.inspect}>"
      end
    end
  end
end
