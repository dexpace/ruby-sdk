# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../http/headers"
require_relative "password_credential"
require_relative "challenge"

module Dexpace
  module Auth
    # AUTH-14: RFC 7617 Basic. One class, two roles, one precomputed value: #call is preemptive
    # stamping -- the path OpenAPI's `http`/`basic` security scheme takes, where a generated SDK
    # sends the credential on the FIRST request and never waits for a 401 -- and
    # #authorization_for is challenge answering, the path ChallengeHandlerChain drives. A second
    # class would compute the same value twice, and AUTH-14 says "computed once and reused".
    #
    # The value is `Basic ` + `["u:p"].pack("m0")`, never Base64: `base64` is a bundled gem from
    # Ruby 3.4 and core may not require it (CLAUDE.md's hard rule; design §6.3). pack("m0")
    # base64-encodes the UTF-8 bytes of the joined string and returns a US-ASCII String, which
    # is the header-safe form AUTH-14 asks for (verified on 3.2.11, 3.4.10 and 4.0.6). A
    # credential in another encoding is transcoded to UTF-8 first, so the bytes packed are the
    # bytes the requirement names.
    #
    # The non-EMPTY check is AUTH-14's own laxer rule -- "permitting whitespace-only values, per
    # RFC 7617" -- and not AUTH-9's non-blank one (6c's P6-3): a password of three spaces is a
    # legal Basic password. Nothing here re-validates the header at the wire; that is the
    # transport adapter's re-validation pass (phase 8).
    #
    # A field that cannot be transcoded to UTF-8 -- a BINARY-tagged one with a high byte, or a
    # UTF-8-tagged one with an invalid sequence, which `encode` to the same encoding passes
    # through unvalidated -- is refused at construction as an InvalidArgumentError naming the
    # FIELD and the two encodings, never the value, and carrying no cause: Ruby's conversion
    # error names the offending byte of the secret, and #full_message renders a cause (AUTH-8;
    # 6c's P6-85, review round 1). InvalidArgumentError's usual "the original left as the
    # cause" rule yields to that, for a credential.
    class BasicHandler
      # @param credential [PasswordCredential]
      # @raise [Dexpace::InvalidArgumentError] on an empty username or password (AUTH-14), a
      #   colon in the username, or a field that is not text UTF-8 can carry
      def initialize(credential)
        credential!(credential)
        pair = "#{utf8!(credential.username, :username)}:#{utf8!(credential.password, :password)}"
        @value = "Basic #{[pair].pack("m0")}".freeze
        freeze
      end

      # Preemptive stamping: the stamper duck type Step takes. Sets rather than adds, so
      # re-stamping a request that already carries the header replaces it.
      #
      # @param request [Dexpace::Request]
      # @return [Dexpace::Request] with `Authorization` set to the precomputed value
      def call(request)
        request.with(headers: request.headers.new_builder.set("Authorization", @value).build)
      end

      # Challenge answering: the same precomputed value, returned only when a Basic challenge
      # was actually offered, accepted case-insensitively (the parser folds the scheme once at
      # construction, so this is an equality test). The header NAME is the chain's to choose
      # from `proxy:` (AUTH-25); this returns the VALUE.
      #
      # @param challenges [Array<Challenge>]
      # @param _request [Dexpace::Request] unused: Basic does not depend on the request
      # @param proxy [Boolean] unused here; the chain selects the header name from it
      # @return [String, nil] the value, or nil when no Basic challenge was offered (AUTH-25)
      def authorization_for(challenges, _request, proxy: false) # rubocop:disable Lint/UnusedMethodArgument -- the handler protocol's signature, which the chain calls uniformly
        return nil unless challenges.any? { |challenge| challenge.scheme == "basic" }

        @value
      end

      private

      def credential!(credential)
        unless credential.is_a?(PasswordCredential)
          raise InvalidArgumentError, "a Dexpace::Auth::PasswordCredential is required"
        end
        if credential.username.empty? || credential.password.empty?
          raise InvalidArgumentError, "username and password must be non-empty (AUTH-14)"
        end
        return unless credential.username.include?(":")

        raise InvalidArgumentError, "a Basic username must not contain a colon (RFC 7617 §2)"
      end

      # AUTH-14 names the UTF-8 bytes of the pair, so each field is transcoded under its own
      # name and must be valid text once it is; the failure is typed, names no value or byte,
      # and carries no cause (see the class comment).
      def utf8!(text, field)
        encoded = text.encode(::Encoding::UTF_8)
        return encoded if encoded.valid_encoding?

        raise not_utf8(text, field), cause: nil
      rescue ::Encoding::UndefinedConversionError, ::Encoding::InvalidByteSequenceError
        raise not_utf8(text, field), cause: nil
      end

      def not_utf8(text, field)
        InvalidArgumentError.new(
          "the #{field} cannot be encoded as UTF-8 from #{text.encoding.name}: a Basic " \
          "credential is the UTF-8 bytes of username:password, and the value is not text " \
          "UTF-8 can carry (AUTH-14)",
        )
      end
    end
  end
end
