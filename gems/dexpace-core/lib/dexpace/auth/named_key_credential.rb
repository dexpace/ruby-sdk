# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../http/header_name"
require_relative "validation"

module Dexpace
  module Auth
    # AUTH-8, AUTH-9, AUTH-26: a named key -- a key NAME that identifies which key is in use
    # (a shared-access-key name, an access-key id) beside the secret key itself. Reference
    # identity, a public validating .new and self-freezing, for the reasons KeyCredential gives.
    #
    # The name stays visible in the renderings: AUTH-8 lists "key name" among the non-secret
    # fields that MAY remain visible, and it is the half a caller needs to see to tell two
    # credentials apart. The key is redacted everywhere.
    class NamedKeyCredential
      # @return [String] the key's name, non-secret (AUTH-8)
      attr_reader :name
      # @return [String] the header the key is stamped into; "Authorization" by default
      attr_reader :header_name
      # @return [String, nil] what precedes the key, separated by one space (AUTH-26)
      attr_reader :prefix

      # @param name [String] non-blank (AUTH-9)
      # @param key [String] non-blank (AUTH-9)
      # @param header_name [String] a valid header name (HTTP-17)
      # @param prefix [String, nil] a non-blank prefix, or nil for none
      def initialize(name:, key:, header_name: "Authorization", prefix: nil)
        @name = Model.frozen_string(Validation.non_blank!("name", name))
        @key = Model.frozen_string(Validation.non_blank!("key", key))
        @header_name = Model.frozen_string(HeaderName.of(header_name).original)
        @prefix = prefix.nil? ? nil : Model.frozen_string(Validation.non_blank!("prefix", prefix))
        freeze
      end

      # The secret, for the stamper. Never rendered.
      #
      # @return [String]
      def key_value = @key

      # @return [String] the key redacted; the name, header name and prefix visible
      def to_s
        "NamedKeyCredential(name=#{@name.inspect}, key=#{REDACTED}, " \
          "header_name=#{@header_name.inspect}, prefix=#{@prefix.inspect})"
      end

      # @return [String] the key redacted; the name, header name and prefix visible
      def inspect
        "#<Dexpace::Auth::NamedKeyCredential name=#{@name.inspect} key=#{REDACTED} " \
          "header_name=#{@header_name.inspect} prefix=#{@prefix.inspect}>"
      end
    end
  end
end
