# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../error/invalid_argument_error"
require_relative "../async/completer"
require_relative "../async/future"
require_relative "bearer_token"
require_relative "provider_error"

module Dexpace
  module Auth
    # AUTH-11: the bearer token provider is a duck type, not a class -- an object answering
    # `#fetch -> BearerToken` and, optionally, `#fetch_async -> Dexpace::Async::Future`. This
    # module names the two shapes for the RBS scan (`_BearerProvider`, `_AsyncBearerProvider`)
    # and ships the one function AUTH-11 fixes: the default async fetch, which "mirrors the
    # blocking fetch's outcome into an already-failed future" for a provider that implements
    # #fetch alone, and normalises "a synchronous throw from a misbehaving async override into
    # a failed future" for one that implements #fetch_async and raises out of it.
    #
    # So `fetch_async` NEVER raises, whatever the provider does: a raise from #fetch, a raise
    # from #fetch_async, a nil token and a non-Future return all become a failed future, and
    # the async stamper reads every provider through this one function. Providers MAY block
    # inside #fetch and SHOULD cache internally; the stamper caches on top regardless.
    module BearerProvider
      extend self

      # @param provider [Object] anything answering #fetch, and optionally #fetch_async
      # @return [Dexpace::Async::Future] settling with the token, or failing with the
      #   provider's own error or a ProviderError
      def fetch_async(provider)
        return mirror(provider) unless provider.respond_to?(:fetch_async)

        future = provider.fetch_async
        return future if future.is_a?(Dexpace::Async::Future)

        failed(ProviderError.new("#fetch_async returned a #{future.class}, not a " \
                                 "Dexpace::Async::Future (AUTH-11)"))
      rescue ::StandardError => error
        failed(error)
      end

      # Whether an object can serve as a provider at all: #fetch is the one required method.
      #
      # @param provider [Object]
      # @return [Boolean]
      def conforms?(provider)
        provider.respond_to?(:fetch)
      end

      private

      # The blocking fetch, mirrored into an already-settled future; a raise from #fetch lands
      # in fetch_async's rescue, as a raise from #fetch_async does.
      def mirror(provider)
        token = provider.fetch
        return failed(ProviderError.new("the provider returned no token (AUTH-35)")) if token.nil?

        completer = Dexpace::Async::Completer.new
        completer.fulfil(token)
        completer.future
      end

      def failed(error)
        completer = Dexpace::Async::Completer.new
        completer.fail(error)
        completer.future
      end
    end
  end
end
