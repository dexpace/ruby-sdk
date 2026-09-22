# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require "async/http"
require_relative "async_http/version"
require_relative "async_http/errors"
require_relative "async_http/drop_policy"
require_relative "async_http/endpoints"
require_relative "async_http/clients"
require_relative "async_http/request_body"
require_relative "async_http/request_mapper"
require_relative "async_http/response_body"
require_relative "async_http/response_mapper"
require_relative "async_http/exchange"
require_relative "async_http/adapter"

module Dexpace
  # Transport adapters: the synchronous and asynchronous transport seams' shipped
  # implementations. The seam contracts themselves live in dexpace-core.
  module Transport
    # The reference asynchronous transport, over the `async-http` gem (phase 8c): the one MVP gem
    # whose reason for existing is to prove the properties a thread pool cannot -- HTTP/2
    # multiplexing, a structured cancellation tree, and suspension at a scheduler checkpoint. One
    # `Async::HTTP::Client` per (reactor, origin) pair, each built with `retries: 0` and a bounded
    # pool; every call is a child task of the caller's own `Async::Task` under its own
    # `with_timeout`, and the returned `Dexpace::Async::Future` is settled from inside it. The
    # adapter creates no reactor: a call from a thread with no `Fiber.scheduler` comes back as an
    # already-failed future carrying Dexpace::SeamError (P8-39, TRANSPORT-21).
    #
    # CAUTION: once dexpace-async-thread is loaded in the same process, `Dexpace::Async` exists,
    # and an unqualified `Async::HTTP` written anywhere under this module resolves through the
    # lexical scope to `Dexpace::Async` before it ever reaches the socketry gem -- and `Dexpace::Async`
    # exists already, in core, so the shadowing is not hypothetical. Every reference to that gem,
    # to `Protocol` and to `OpenSSL` from inside here is written `::`-qualified, and the gem's
    # smoke suite scans lib/ for an unqualified one.
    module AsyncHTTP
      extend self

      # The configured tier's fallback for RequestOptions#timeout: the per-call budget when
      # neither the call nor the transport nor Configuration::Keys::REQUEST_TIMEOUT says
      # otherwise. The same key and the same default as dexpace-transport-net_http, so one caller
      # setting governs both transports (the charter's shared transport contracts, item 4).
      DEFAULT_TIMEOUT_SECONDS = 60.0

      # The per-origin connection limit when Configuration::Keys::TRANSPORT_CONNECTION_LIMIT is
      # unset: async-http's own default is an UNBOUNDED pool (eight concurrent requests opened
      # seven connections in the design's measurement), and an SDK that hands a caller an
      # unbounded file-descriptor budget has decided on the caller's behalf. Chosen, not derived.
      DEFAULT_CONNECTION_LIMIT = 8

      # XCUT-14's hard cap on the client map: (reactor, origin) pairs, drained back under it in a
      # loop after every insert, each evicted client's pool retired. A memory backstop and never
      # the primary cleanup -- `#close` is.
      MAX_ORIGINS = 32

      # The key the require-time registration below uses, and the key a caller passes to
      # Dexpace::AsyncTransport when they want this adapter by name.
      REGISTRY_KEY = :async_http

      # TRANSPORT-11's drop set: the same ten folded names dexpace-transport-net_http drops under
      # its MANAGED_HEADERS (the charter's shared transport contracts, item 1; the membership is
      # shared, the constant is per gem because NFR-2 forbids either gem depending on the other).
      # More load-bearing here than there: async-http APPENDS a caller-set `host`, `content-length`
      # or `transfer-encoding` beside the one it writes itself, which is the canonical
      # Host-duplication and CL.CL / TE.CL request-smuggling shape (the design's verified fact 5).
      # A drop from this set is always logged at VERBOSE and never goes through DropPolicy.
      FRAMING_HEADERS = %w[
        host content-length transfer-encoding connection keep-alive proxy-connection te trailer
        upgrade expect
      ].freeze

      # What the adapter's own TLS context offers by ALPN: HTTP/2 preferred, HTTP/1.1 admitted.
      # A caller-supplied `ssl_context:` is used verbatim and never has this set on it.
      ALPN_PROTOCOLS = %w[h2 http/1.1].freeze

      # The SDK-managed construction: builds and owns its clients, one per (reactor, origin), and
      # closes them all on `#close` by retiring every pooled connection without waiting (P8-37).
      #
      # The budget's three tiers, highest first: `RequestOptions#timeout` on the call, `timeout:`
      # here, then `Configuration::Keys::REQUEST_TIMEOUT` -- read through `Configuration#duration`,
      # whose grammar treats a BARE number as milliseconds (CFG-7): `REQUEST_TIMEOUT=30` is thirty
      # milliseconds, and thirty seconds is `30s` or `PT30S` -- and finally
      # DEFAULT_TIMEOUT_SECONDS. The budget bounds the exchange up to the response head: the
      # body streams under no deadline (IO-40), and the deadline interrupts only at a scheduler
      # checkpoint (design §8.3).
      #
      # `ssl_context:` replaces the adapter's own TLS context for every https origin, whole rather
      # than per knob, so the SDK never becomes a partial re-export of OpenSSL's surface; the
      # caller's context is used verbatim, ALPN included -- a context with no `alpn_protocols`
      # negotiates HTTP/1.1. With none, the adapter's own context verifies the peer against the
      # default certificate store for EVERY host, including `localhost`, which async-http's own
      # default would have silently left unverified.
      #
      # @param timeout [Numeric, nil] the per-transport default budget in seconds; nil defers to
      #   the configuration chain
      # @param logger [Dexpace::Instrumentation::Logger] where header drops are logged; defaults
      #   to the null logger so no caller holds a nil
      # @param drop_policy [DropPolicy, nil] TRANSPORT-13's drop-logging policy; nil is
      #   DropPolicy's once-per-name default
      # @param connection_limit [Integer, nil] the per-origin pool bound; nil reads
      #   Configuration::Keys::TRANSPORT_CONNECTION_LIMIT, then DEFAULT_CONNECTION_LIMIT
      # @param ssl_context [OpenSSL::SSL::SSLContext, nil] a caller's whole TLS context, or nil
      # @param configuration [Dexpace::Configuration, nil] the chain the limit and the configured
      #   timeout are read from; nil is the process-wide Dexpace.configuration
      # @return [Adapter] an owning adapter (`#owned?` is true)
      # @raise [Dexpace::InvalidArgumentError] for a `timeout:` that is not nil or a finite,
      #   positive number
      def build(timeout: nil, logger: ::Dexpace::Instrumentation::Logger::NULL, drop_policy: nil,
                connection_limit: nil, ssl_context: nil, configuration: nil)
        Adapter.owning(timeout: timeout, logger: logger, drop_policy: drop_policy,
                       connection_limit: connection_limit, ssl_context: ssl_context,
                       configuration: configuration,)
      end

      # The borrowing construction: the caller's own `Async::HTTP::Client` carries every request
      # whatever its origin, and the adapter never closes it -- the caller may keep using it after
      # the transport is closed (TRANSPORT-15, XCUT-22). Two consequences are the contract: the
      # client is bound to the reactor it was built for, exactly as any async-http client is; and
      # `retries` must already be zero, which the adapter asserts rather than sets, because
      # TRANSPORT-2 scopes the disable to an SDK-managed transport and XCUT-22 forbids mutating a
      # caller's object.
      #
      # @param client [Async::HTTP::Client] the caller's client, with `retries` zero
      # @param logger [Dexpace::Instrumentation::Logger] as for `.build`
      # @param drop_policy [DropPolicy, nil] as for `.build`
      # @return [Adapter] a borrowing adapter (`#owned?` is false)
      # @raise [Dexpace::InvalidArgumentError] when the client's `retries` is not zero
      def using(client, logger: ::Dexpace::Instrumentation::Logger::NULL, drop_policy: nil)
        Adapter.borrowing(client, logger: logger, drop_policy: drop_policy)
      end

      # SEAM-5's zero-argument factory the registry calls: a FRESH owning adapter every call,
      # never a memoized one, because a memoized default would be one adapter shared across
      # every unconfigured consumer in the process.
      #
      # @return [Adapter]
      def default
        build
      end

      # Require-time self-registration, the one load-time side effect this repository permits:
      # the LAST statement inside the module, so `method(:default)` resolves against it. The
      # `core:` keyword is phase 2's version-skew guard and raises Dexpace::SeamError on a
      # Dexpace::VERSION mismatch (design §2.4). Explicit, never presence-gated: this adapter
      # registers because it was required, never because `Async::HTTP` happens to be defined.
      ::Dexpace::AsyncTransport.register(
        REGISTRY_KEY, method(:default),
        core: "~> #{::Dexpace::VERSION.split(".").first(2).join(".")}",
      )
    end
  end
end
