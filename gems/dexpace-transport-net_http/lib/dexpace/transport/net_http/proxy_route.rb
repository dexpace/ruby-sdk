# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module NetHTTP
      # R17 (TRANSPORT-30): the four values for Net::HTTP.new's p_addr, p_port, p_user and
      # p_pass, all nil when no proxy applies -- and an EXPLICIT nil is the point: Net::HTTP.new's
      # p_addr defaults to :ENV, which routes through `http_proxy` with a credential this SDK
      # never resolved and a bypass list it never consulted. The values come from phase 5a's
      # Dexpace::Proxy.resolve, the resolver's first consumer in the repository. A private_constant
      # snapshot, so a plain Data without the construction pattern (phase 2's P2-9).
      ProxyRoute = ::Data.define(:address, :port, :username, :password) do
        # The direct route.
        #
        # @return [ProxyRoute]
        def self.none
          new(address: nil, port: nil, username: nil, password: nil)
        end

        # @param url [URI::Generic] this call's target, for CFG-23's per-host bypass decision
        # @param configuration [Dexpace::Configuration] the chain the proxy is resolved from
        # @param logger [Dexpace::Instrumentation::Logger] where an unhonourable proxy feature is
        #   warned about
        # @return [ProxyRoute]
        def self.for(url, configuration: ::Dexpace.configuration,
                     logger: ::Dexpace::Instrumentation::Logger::NULL)
          proxy = ::Dexpace::Proxy.resolve(configuration, logger: logger)
          return none if proxy.nil?

          from(proxy, url, logger: logger)
        end

        # @param proxy [Dexpace::Proxy] a resolved proxy
        # @param url [URI::Generic] this call's target
        # @param logger [Dexpace::Instrumentation::Logger]
        # @return [ProxyRoute]
        def self.from(proxy, url, logger: ::Dexpace::Instrumentation::Logger::NULL)
          return none if proxy.bypass?(url.hostname.to_s)

          warn_unhonoured(proxy, logger)
          new(address: proxy.host, port: proxy.port, username: proxy.username,
              password: proxy.password,)
        end

        # TRANSPORT-30's SHOULD: "a custom (non-Basic) proxy challenge handler SHOULD be surfaced
        # with a WARN and proxy auth SHOULD fall back to Basic from username/password". Net::HTTP
        # speaks Basic through p_user/p_pass and nothing else, and no SOCKS at all, so those are
        # the two unhonourable features and both take the same warning. The event names the
        # feature and never a credential -- the first embedded MUST.
        def self.warn_unhonoured(proxy, logger)
          reasons = [] #: Array[String]
          reasons << "a custom proxy challenge handler" unless proxy.challenge_handler.nil?
          unless proxy.type == ::Dexpace::Proxy::Type::HTTP
            reasons << "proxy type #{proxy.type.name}"
          end
          return if reasons.empty?

          ::Dexpace::Instrumentation.contain(logger, event: PROXY_LIMITATION_EVENT) do
            logger.event(::Dexpace::Instrumentation::Severity::WARNING)
              .event(PROXY_LIMITATION_EVENT)
              .field("unhonoured", reasons.join(", "))
              .field("remedy", "Basic proxy authentication from the proxy's username and password")
              .emit
          end
        end
      end

      private_constant :ProxyRoute
    end
  end
end
