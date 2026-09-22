# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "openssl"

module Dexpace
  module Transport
    module AsyncHTTP
      # Dexpace::Request#url -> Async::HTTP::Endpoint, and the origin the client map is keyed on.
      #
      # Never calls Async::HTTP::Endpoint.parse: that method routes through URI.parse, i.e.
      # URI::DEFAULT_PARSER, which IS URI::RFC3986_PARSER on 3.4 and RFC2396_PARSER below it --
      # the straddle design §3.5 pins against everywhere else. Dexpace::URL.parse! already parsed
      # the request's URL with URI::RFC3986_PARSER at phase 1's construction time, and
      # Endpoint.new takes that object as it is (the design's verified fact 13). A private_constant
      # of AsyncHTTP.
      module Endpoints
        extend self

        # The two schemes this transport can dispatch. Dexpace::URL.parse! admits `ftp://` and
        # Endpoint.new would dial its port 21, so the screen is here and the answer is
        # InvalidArgumentError through the future (TRANSPORT-21), never a connect to the wrong
        # service (the same screen 6b's Location and 7c's next-page target apply).
        SCHEMES = %w[http https].freeze
        private_constant :SCHEMES

        # @param url [URI::Generic] the request's already-parsed URL
        # @param ssl_context [OpenSSL::SSL::SSLContext, nil] a caller's context, used verbatim
        # @return [Async::HTTP::Endpoint]
        # @raise [Dexpace::InvalidArgumentError] for a scheme other than http or https
        def for(url, ssl_context: nil)
          screen!(url)
          return ::Async::HTTP::Endpoint.new(url) if url.scheme.to_s.downcase == "http"

          ::Async::HTTP::Endpoint.new(url, ssl_context: ssl_context || default_ssl_context)
        end

        # The screen, run by RequestMapper before the request target is read -- a URI::FTP has
        # no `#request_uri` -- and by #for before an endpoint is built.
        #
        # @param url [URI::Generic]
        # @return [nil]
        # @raise [Dexpace::InvalidArgumentError] for a scheme other than http or https
        def screen!(url)
          return nil if SCHEMES.include?(url.scheme.to_s.downcase)

          raise ::Dexpace::InvalidArgumentError,
                "the async transport dispatches http and https only, got the scheme " \
                "#{url.scheme.inspect} (TRANSPORT-21)"
        end

        # The origin: scheme, host and port, folded, so two URLs on one origin share one client
        # and one pool (TRANSPORT-29's "same native client" is per origin here).
        #
        # @param url [URI::Generic]
        # @return [Array(String, String, Integer)] frozen
        def origin_for(url)
          [url.scheme.to_s.downcase, url.host.to_s.downcase, url.port].freeze
        end

        private

        # The two library defaults this adapter overrides (the design's TLS defaults): the
        # endpoint's own `ssl_verify_mode` is VERIFY_NONE for any hostname matching `localhost`,
        # which is a convenience in a web framework and a silent downgrade in an SDK; and a
        # caller-supplied context is used verbatim with `alpn_protocols` never set on it, so
        # HTTP/2 over TLS is unreachable unless something sets it. This is the something, and
        # `set_params` with VERIFY_PEER also installs the default certificate store and hostname
        # verification -- filesystem I/O, which is why Clients builds outside its lock.
        def default_ssl_context
          context = ::OpenSSL::SSL::SSLContext.new
          context.set_params(verify_mode: ::OpenSSL::SSL::VERIFY_PEER)
          context.alpn_protocols = ALPN_PROTOCOLS
          context
        end
      end

      private_constant :Endpoints
    end
  end
end
