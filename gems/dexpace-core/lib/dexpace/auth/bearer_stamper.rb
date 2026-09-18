# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../http/headers"
require_relative "../clock"
require_relative "bearer_token"
require_relative "bearer_provider"
require_relative "provider_error"

module Dexpace
  module Auth
    # AUTH-11 (sync half), AUTH-34, AUTH-35, AUTH-36's cache half: the synchronous bearer
    # stamper -- one cached token per credential, refreshed through the provider a configurable
    # margin before its expiry, with single-flight coordination so concurrent requests racing
    # on a missing or expiring token cost at most one fetch.
    #
    # The hot path takes no lock (XCUT-12): #call reads @token, one frozen BearerToken published
    # by a write under @lock, and stamps it when it is fresh. Safe by publication rather than by
    # the GVL -- the reference is written once, under the mutex, and the object it points to is
    # immutable -- so it holds on every Ruby. The slow path acquires @lock, re-checks (the
    # double-check), and calls the provider WHILE HOLDING IT: the one sanctioned exception to
    # "never hold a mutex across a suspension point" (XCUT-12's own text), because serialising
    # the fetch is exactly what single-flight means, and the lock is this credential's own, so
    # it can serialise nothing else.
    #
    # AUTH-35's rejections -- a nil token, a token already expired at fetch time with NO margin,
    # a non-BearerToken -- raise ProviderError from inside the lock with @token untouched, and a
    # provider that raises propagates its own error the same way; nothing is cached on any of
    # those paths, so a later request retries (AUTH-11).
    class BearerStamper
      # AUTH-34's default refresh margin, in seconds.
      DEFAULT_REFRESH_MARGIN = 30

      # @param provider [Object] anything answering #fetch -> BearerToken
      # @param clock [_Clock] the time seam; Clock::SYSTEM by default
      # @param refresh_margin [Numeric] seconds before expiry at which a token is refreshed
      def initialize(provider:, clock: Clock::SYSTEM, refresh_margin: DEFAULT_REFRESH_MARGIN)
        unless BearerProvider.conforms?(provider)
          raise InvalidArgumentError, "provider must answer #fetch (AUTH-11)"
        end
        unless refresh_margin.is_a?(::Numeric) && !refresh_margin.negative?
          raise InvalidArgumentError, "refresh_margin must be a non-negative number of seconds"
        end

        @provider = provider
        @clock = clock
        @refresh_margin = refresh_margin
        @lock = ::Thread::Mutex.new
        @token = nil #: BearerToken?
      end

      # The stamper duck type Step takes: `Authorization: Bearer <token>`, set rather than
      # added so a re-stamp replaces.
      #
      # @param request [Dexpace::Request]
      # @return [Dexpace::Request]
      # @raise [ProviderError] on a misbehaving provider result (AUTH-35)
      def call(request)
        token = @token # the hot path: no lock (XCUT-12)
        token = refresh! if token.nil? || token.expired?(now: @clock.now, margin: @refresh_margin)
        request.with(headers: request.headers.new_builder.set("Authorization", header(token)).build)
      end

      # AUTH-36's cache half: clear the cached token iff its stamped header value is exactly
      # the rejected one -- compare-and-clear under the lock, on the HEADER VALUE and never on
      # credential equality. A token another request already refreshed no longer matches, and
      # survives; the Boolean says which happened, so the step can re-stamp from the cache in
      # that case and fetch afresh in the other.
      #
      # @param rejected_header [String] the Authorization value the 401 rejected
      # @return [Boolean] whether the cached token was the rejected one and was evicted
      def evict_if_matches(rejected_header)
        @lock.synchronize do
          token = @token
          next false if token.nil? || header(token) != rejected_header

          @token = nil
          true
        end
      end

      private

      def header(token) = "Bearer #{token.token}"

      # The slow path, and XCUT-12's sanctioned lock-across-fetch.
      def refresh!
        @lock.synchronize do
          token = @token
          return token if !token.nil? && !token.expired?(now: @clock.now, margin: @refresh_margin)

          fetched = validate(@provider.fetch)
          @token = fetched # written only on success: a raise above leaves the cache untouched
        end
      end

      # AUTH-35: non-nil, a BearerToken, and not already expired with NO margin.
      def validate(fetched)
        raise ProviderError, "the provider returned no token (AUTH-35)" if fetched.nil?
        unless fetched.is_a?(BearerToken)
          raise ProviderError, "the provider returned a #{fetched.class}, not a BearerToken"
        end
        if fetched.expired?(now: @clock.now, margin: 0)
          raise ProviderError, "the provider returned a token already expired at fetch time"
        end

        fetched
      end
    end
  end
end
