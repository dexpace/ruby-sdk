# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # The client map: one `Async::HTTP::Client` per (reactor, origin) pair, and the object
      # P8-37 and the XCUT-14 cap live on.
      #
      # Keyed by the REACTOR as well as the origin, because one async-http client cannot be
      # shared across OS threads that each run their own reactor: its pool waits on a
      # Thread::Mutex and a ConditionVariable that are not the scheduler's to interrupt, and a
      # fiber resumed across threads raises. Measured: two threads with a reactor each, ten GETs
      # apiece through one client, never completed; one client per thread, forty of forty. So
      # every thread running its own reactor gets its own client per origin, fibers inside ONE
      # reactor share one multiplexed client, and ASYNC-22's "concurrent calls from multiple
      # threads" holds structurally. The reactor is `Fiber.scheduler` at the call, compared by
      # identity through Data's member equality, never by class.
      #
      # #fetch's critical section is a Hash read and a Hash insert and nothing else: the client is
      # built OUTSIDE the lock, because Endpoints loads the default certificate store from disk
      # for an https origin -- filesystem I/O, a scheduler suspension point, which
      # concurrency-and-async/ee54cb68 forbids a lock being held across. A lost race discards an
      # unused client, which costs nothing: Client.new opens no socket. A private_constant of
      # AsyncHTTP.
      class Clients
        # The map's key: the calling fiber's scheduler and the request's origin.
        Key = ::Data.define(:reactor, :origin)
        private_constant :Key

        private_class_method :new

        # @param configuration [Dexpace::Configuration]
        # @param connection_limit [Integer, nil] an explicit per-origin bound, else the
        #   configuration's TRANSPORT_CONNECTION_LIMIT, else DEFAULT_CONNECTION_LIMIT
        # @param ssl_context [OpenSSL::SSL::SSLContext, nil] a caller's TLS context, or nil
        # @return [Clients]
        # @raise [Dexpace::InvalidArgumentError] for a limit that is not a positive Integer
        def self.build(configuration:, connection_limit: nil, ssl_context: nil)
          limit = connection_limit || configuration.integer(
            ::Dexpace::Configuration::Keys::TRANSPORT_CONNECTION_LIMIT,
            default: DEFAULT_CONNECTION_LIMIT,
          )
          unless limit.is_a?(::Integer) && limit.positive?
            raise ::Dexpace::InvalidArgumentError,
                  "connection_limit must be a positive Integer, got #{limit.inspect}"
          end

          new(limit: limit, ssl_context: ssl_context)
        end

        def initialize(limit:, ssl_context:)
          @limit = limit
          @ssl_context = ssl_context
          @mutex = ::Thread::Mutex.new
          @by_key = {}
        end

        # @return [Integer] the per-origin pool bound every client is built with
        attr_reader :limit

        # The client for this request's origin under the calling fiber's reactor, built on first
        # use. XCUT-14: the insert drains back to MAX_ORIGINS in a LOOP under the same lock as the
        # insert -- a client whose reactor has since closed first, then the oldest -- and every
        # evicted client's pool is retired OUTSIDE the lock, because the values own pools and a
        # dropped pool is a connection leak wearing a cap.
        #
        # @param url [URI::Generic] the request's URL
        # @param reactor [Object] the calling fiber's scheduler, compared by identity
        # @return [Async::HTTP::Client]
        def fetch(url, reactor:)
          key = Key.new(reactor: reactor, origin: Endpoints.origin_for(url))
          existing = @mutex.synchronize { @by_key[key] }
          return existing if existing

          candidate = build_client(url)
          client = nil
          evicted = [] #: Array[untyped]
          @mutex.synchronize do
            client = (@by_key[key] ||= candidate)
            drain(evicted)
          end
          evicted.each { |old| Clients.release(old) }
          client
        end

        # XCUT-14's bound, asserted rather than assumed.
        #
        # @return [Integer]
        def size
          @mutex.synchronize { @by_key.size }
        end

        # Releases every client without waiting on any of them (P8-37).
        #
        # @return [nil]
        def close
          clients = @mutex.synchronize { @by_key.values.tap { @by_key.clear } }
          clients.each { |client| Clients.release(client) }
          nil
        end

        # P8-37, as built: `Async::HTTP::Client#close` is `@pool.wait_until_free { Console.warn … }`
        # then `@pool.close`, and async-pool's `Controller#close` is itself a `drain` that waits on
        # a condition while any resource is busy -- both bounded only by the SERVER, and the first
        # writes a JSON warning to the host's stderr on the way. Measured with one request in
        # flight against a two-second server: 1951 ms each. The route that returns at once is to
        # retire every resource first -- `Controller#retire` and `#resources` are public API --
        # after which `#close` has nothing to wait for. A connection still in flight is retired
        # rather than waited on: the exchange holding it surfaces a wrapped, retryable
        # Dexpace::TransportError, which is what closing a transport mid-flight means
        # (TRANSPORT-16, XCUT-13). Works outside any reactor too, which `Adapter#close` from a
        # test's teardown or a caller's `ensure` relies on.
        #
        # @param client [Async::HTTP::Client]
        # @return [nil]
        def self.release(client)
          pool = client.pool
          pool.resources.each_key { |resource| pool.retire(resource) }
          ::Dexpace.close_quietly(pool)
        end

        private

        # Under the lock: back to MAX_ORIGINS, closed reactors first, then the oldest.
        def drain(evicted)
          return if @by_key.size <= MAX_ORIGINS

          evict_closed_reactors(evicted)
          evicted << @by_key.delete(@by_key.keys.first) while @by_key.size > MAX_ORIGINS
        end

        def evict_closed_reactors(evicted)
          @by_key.delete_if do |key, client|
            next false unless key.reactor.respond_to?(:closed?) && key.reactor.closed?

            evicted << client
            true
          end
        end

        # `retries: 0` is TRANSPORT-2, TRANSPORT-17 and TRANSPORT-18 on this adapter: the default
        # is 3 and the SDK pipeline is the single retry authority. `limit:` reaches the pool.
        def build_client(url)
          endpoint = Endpoints.for(url, ssl_context: @ssl_context)
          ::Async::HTTP::Client.new(endpoint, retries: 0, limit: @limit)
        end
      end

      private_constant :Clients
    end
  end
end
