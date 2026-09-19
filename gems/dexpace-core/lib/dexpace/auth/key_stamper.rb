# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../error/invalid_argument_error"
require_relative "../http/headers"
require_relative "../http/header_syntax"

module Dexpace
  module Auth
    # AUTH-26: static key-credential stamping. Constructed against a KeyCredential or a
    # NamedKeyCredential -- anything answering #header_name, #prefix and #key_value -- it
    # computes the header value once and is stateless after construction: #call reads two frozen
    # Strings and writes one header. The prefix, when there is one, precedes the key with
    # exactly one space (`SharedAccessKey <key>`).
    #
    # The write is a SET, not an add, through the phase-1 idiom for a derived request
    # (`request.with(headers: request.headers.new_builder.set(…).build)`): re-stamping a request
    # that already carries the header replaces the value, where Request::Builder#header would
    # append a second one. The value is checked against the outbound header grammar here, so a
    # key that could never be sent fails at construction rather than at every request.
    class KeyStamper
      # @param credential [KeyCredential, NamedKeyCredential]
      # @raise [Dexpace::InvalidArgumentError] when the credential lacks the three readers, or
      #   its rendered value cannot be carried by a header (HTTP-18)
      def initialize(credential)
        unless %i[header_name prefix key_value].all? { |reader| credential.respond_to?(reader) }
          raise InvalidArgumentError,
                "a key credential answering #header_name, #prefix and #key_value is required"
        end

        prefix = credential.prefix
        value = prefix.nil? ? credential.key_value : "#{prefix} #{credential.key_value}"
        unless HeaderSyntax.valid_outbound_value?(value)
          raise InvalidArgumentError,
                "the key for header #{credential.header_name} contains a byte no outbound " \
                "header value may carry (HTTP-18)"
        end

        @header_name = credential.header_name
        @value = value.frozen? ? value : value.dup.freeze
        freeze
      end

      # @param request [Dexpace::Request]
      # @return [Dexpace::Request] with the credential's header set to the key value
      def call(request)
        request.with(headers: request.headers.new_builder.set(@header_name, @value).build)
      end
    end
  end
end
