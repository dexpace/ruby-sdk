# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../http/headers"
require_relative "../clock"
require_relative "../async/completer"
require_relative "../async/future"
require_relative "../error/cancelled_error"
require_relative "../instrumentation/keys"
require_relative "../instrumentation/logger"
require_relative "../instrumentation/contain"
require_relative "bearer_token"
require_relative "bearer_provider"
require_relative "bearer_stamper"
require_relative "provider_error"

module Dexpace
  module Auth
    # AUTH-37, AUTH-36's async half, AUTH-11: the bearer stamper for the async runtime and
    # 6c's R12 as code. It never calls #value or #wait on any future -- the calling fiber
    # returns as soon as it has something to hand back -- and it spawns no thread: "kick off an
    # off-thread background refresh" means calling the provider's async fetch and attaching
    # #on_settle, and whatever runs the fetch is the provider's own affair (6c's P6-5).
    #
    # Three zones, read off one lock-free token reference (XCUT-12): FRESH (not expired with
    # the margin) stamps and makes no provider call; EXPIRING-BUT-VALID (expired with the
    # margin, not without it) stamps the still-valid token at once and kicks off a refresh it
    # does not await; EXPIRED-OR-MISSING settles a Completer of its own from the in-flight
    # fetch's settlement -- R12's "second #on_settle and a second Completer". Every refresh goes
    # through ONE single-flight slot: the first caller registers a Completer under @lock and
    # starts the fetch; every later caller, from either zone, coalesces onto that future. A
    # failed fetch settles the waiters with the error and caches nothing; a failed BACKGROUND
    # refresh is reported through `logger:` as an `http.auth.refresh` diagnostic and fails
    # nothing, since a valid token was already stamped.
    #
    # The fetch is shared; a cancellation is not. The waiter's future is settled FROM the slot's
    # and never wired back to it: Future#then would register the derived future's cancellation
    # against its source, which here is the one slot every coalesced caller and every arrival
    # until the provider settles share, so cancelling one request's future would cancel them
    # all (review round 2). Cancelling a waiter detaches that waiter alone -- the fetch runs on,
    # the token is cached, the other waiters stamp it. Only the provider's own settlement
    # settles the slot, and a cancellation there is forwarded as a cancellation, not as a plain
    # failure, so `#cancelled?` stays true one link down (SEAM-18, 4c's rule).
    #
    # The fetch is started OUTSIDE the lock, and that is not a style choice. AUTH-11's default
    # wrapper mirrors a sync-only provider's #fetch into an ALREADY-SETTLED future, on which
    # phase 2's #on_settle runs the block inline on the calling fiber; the settle block takes
    # the lock to publish the token, and Thread::Mutex is not reentrant, so starting the fetch
    # inside `synchronize` raises `ThreadError: deadlock; recursive locking` for the commonest
    # provider shape there is (verified on 3.2.11, 3.4.10 and 4.0.6). Register, release, fetch.
    #
    # #stamp_fresh is the post-eviction path AUTH-37's last clause names: it bypasses the
    # three-zone read and settles on a coalesced fetch, so the retry can never re-send the
    # token the server just rejected. AsyncStep calls it after a successful eviction, and
    # #stamp after a failed one, where AUTH-36 says the refreshed token is reused.
    class AsyncBearerStamper # rubocop:disable Metrics/ClassLength -- R12's two Completers written out: the slot, the waiter settled from it and never wired back, and the one SEAM-18 classification both settle by; see the class comment
      # @param provider [Object] anything answering #fetch, and optionally #fetch_async
      # @param clock [_Clock] the time seam; Clock::SYSTEM by default
      # @param refresh_margin [Numeric] seconds before expiry at which a token is refreshed
      # @param logger [Instrumentation::Logger] where a failed background refresh is reported;
      #   Logger::NULL reports nothing
      def initialize(provider:, clock: Clock::SYSTEM,
                     refresh_margin: BearerStamper::DEFAULT_REFRESH_MARGIN,
                     logger: Instrumentation::Logger::NULL)
        unless BearerProvider.conforms?(provider)
          raise InvalidArgumentError, "provider must answer #fetch (AUTH-11)"
        end
        unless refresh_margin.is_a?(::Numeric) && !refresh_margin.negative?
          raise InvalidArgumentError, "refresh_margin must be a non-negative number of seconds"
        end

        @provider = provider
        @clock = clock
        @refresh_margin = refresh_margin
        @logger = Model.required!("logger", logger)
        @lock = ::Thread::Mutex.new
        @token = nil #: BearerToken?
        @in_flight = nil #: Dexpace::Async::Future?
      end

      # The three-zone policy. Returns a future of the stamped request.
      #
      # @param request [Dexpace::Request]
      # @return [Dexpace::Async::Future]
      def stamp(request)
        token = @token # the hot path: no lock (XCUT-12)
        return awaiting(request) if token.nil?

        case zone(token)
        when :fresh
          settled(stamp_with(request, token)) # no provider call
        when :expiring
          background_refresh # stamp now, refresh without awaiting
          settled(stamp_with(request, token))
        else
          awaiting(request) # expired
        end
      end

      # AUTH-37's post-eviction clause: always a coalesced fetch, never the cache.
      #
      # @param request [Dexpace::Request]
      # @return [Dexpace::Async::Future]
      def stamp_fresh(request)
        awaiting(request)
      end

      # AUTH-36's cache half, identical to BearerStamper#evict_if_matches.
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

      # AUTH-37's three zones of a cached token, from one clock reading: :fresh (not expired
      # with the margin), :expiring (expired with the margin, valid without it), :expired.
      def zone(token)
        now = @clock.now
        return :fresh unless token.expired?(now: now, margin: @refresh_margin)

        token.expired?(now: now, margin: 0) ? :expired : :expiring
      end

      # The expired-or-missing zone's return: this request's own Completer, settled from the
      # coalesced fetch's settlement and never blocking. Not Future#then -- see the class
      # comment for why the waiter must not be wired back to the shared slot.
      def awaiting(request)
        own = Dexpace::Async::Completer.new
        refresh_future.on_settle { |settlement| deliver(settlement, request, own) }
        own.future
      end

      # The waiter's settlement from the slot's. The rescue keeps a raising stamp (a token the
      # outbound header grammar refuses) on this side of the settling thread, as a failure of
      # this waiter alone.
      def deliver(settlement, request, own)
        settle(own, settlement, settlement.error) { |token| stamp_with(request, token) }
      rescue ::StandardError => error
        own.fail(error)
      end

      def header(token) = "Bearer #{token.token}"

      def stamp_with(request, token)
        request.with(headers: request.headers.new_builder.set("Authorization", header(token)).build)
      end

      # An already-settled future over a value: the fresh and expiring zones' return.
      def settled(request)
        completer = Dexpace::Async::Completer.new
        completer.fulfil(request)
        completer.future
      end

      # The single-flight slot. Under the lock: reuse the in-flight future or register a new
      # Completer. Outside it: start the fetch. See the class comment for why that order is
      # load-bearing.
      def refresh_future
        completer = Dexpace::Async::Completer.new # discarded when a fetch is already in flight
        existing = @lock.synchronize do
          in_flight = @in_flight
          @in_flight = completer.future if in_flight.nil?
          in_flight
        end
        return existing unless existing.nil?

        start_fetch(completer)
        completer.future
      end

      # The fetch, and the one place the token is published. BearerProvider.fetch_async never
      # raises, so the only way out of here is the settle block, which clears the slot and
      # writes the cache under the lock and then settles the waiters outside it. A settle
      # block that raised would propagate into whoever settled the provider's future, so
      # nothing in it can raise: Completer#fulfil, #fail and #request_cancel report rather
      # than raise. A provider that cancels its own fetch cancels the slot, and through it every
      # waiter, as a cancellation.
      def start_fetch(completer)
        BearerProvider.fetch_async(@provider).on_settle do |settlement|
          token = settlement.success? ? settlement.response : nil
          error = settlement.error || invalid(token)
          @lock.synchronize do
            @in_flight = nil
            @token = token if error.nil?
          end
          settle(completer, settlement, error) { token }
        end
      end

      # The one classification both completers settle by, Future#then's three rules: a
      # cancellation of `settlement` stays a cancellation (SEAM-18), any other `error` is the
      # same object, and a success settles with what the block makes of the response.
      def settle(target, settlement, error)
        if error.nil?
          target.fulfil(yield(settlement.response))
        elsif settlement.cancelled && error.is_a?(Dexpace::CancelledError)
          target.request_cancel(error.reason)
        else
          target.fail(error)
        end
      end

      # AUTH-35's rejections as an error value, or nil for a usable token.
      def invalid(token)
        return ProviderError.new("the provider returned no token (AUTH-35)") if token.nil?
        unless token.is_a?(BearerToken)
          return ProviderError.new("the provider returned a #{token.class}, not a BearerToken")
        end
        return nil unless token.expired?(now: @clock.now, margin: 0)

        ProviderError.new("the provider returned a token already expired at fetch time")
      end

      # The expiring zone's refresh: coalesced like any other, observed only to log a failure.
      # AUTH-37: "a failed/unusable BACKGROUND refresh MUST NOT fail the in-flight request
      # (log-and-continue)" -- there is no in-flight request left to fail.
      def background_refresh
        refresh_future.on_settle do |settlement|
          next if settlement.success?

          Instrumentation.diagnostic(@logger, event: Instrumentation::Events::AUTH_REFRESH,
                                              cause: settlement.error,)
        end
      end
    end
  end
end
