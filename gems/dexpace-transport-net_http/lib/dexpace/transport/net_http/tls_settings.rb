# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module NetHTTP
      # R18: `.build`'s `tls:` keyword, validated once at construction and applied to each per-call
      # client only when the request is `https`. Plain values only -- a path String, an OpenSSL
      # object the CALLER built, a Symbol version -- so nothing here is named in a public
      # signature: `tls:` is typed `untyped` in sig/ with a YARD block listing TLS_SETTINGS,
      # because OpenSSL::X509::Certificate, OpenSSL::PKey::RSA and OpenSSL::SSL::VERIFY_PEER are
      # all constants NFR-11's scan rejects. A private_constant of NetHTTP.
      module TLSSettings
        extend self

        # @param settings [Hash, nil] see NetHTTP::TLS_SETTINGS
        # @return [Hash] frozen, possibly empty
        # @raise [Dexpace::InvalidArgumentError] for a non-Hash, or for a key outside
        #   TLS_SETTINGS -- a silently ignored `verify_mode:` is a security setting the caller
        #   believes they set
        def validate!(settings)
          if settings.nil?
            none = {} #: Hash[Symbol, untyped]
            return none.freeze
          end

          unless settings.is_a?(::Hash)
            raise ::Dexpace::InvalidArgumentError,
                  "tls: takes a Hash of #{TLS_SETTINGS.join(", ")} or nil, not a #{settings.class}"
          end

          unknown = settings.keys - TLS_SETTINGS
          unless unknown.empty?
            raise ::Dexpace::InvalidArgumentError,
                  "tls: does not accept #{unknown.map(&:inspect).join(", ")}; accepted keys are " \
                  "#{TLS_SETTINGS.join(", ")}"
          end

          settings.dup.freeze
        end

        # Assigns only the keys the caller passed, so the default path assigns NOTHING and
        # OpenSSL's own VERIFY_PEER-with-hostname-verification defaults survive. The adapter never
        # weakens a default on its own.
        #
        # @param http [Net::HTTP] an unstarted, owned client with `use_ssl` on
        # @param settings [Hash] the validated settings
        # @return [nil]
        def apply(http, settings)
          settings.each { |key, value| http.public_send(:"#{key}=", value) }
          nil
        end
      end

      private_constant :TLSSettings
    end
  end
end
