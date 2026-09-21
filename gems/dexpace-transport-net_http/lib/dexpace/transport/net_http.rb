# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require "net/http"
require_relative "net_http/version"
require_relative "net_http/deadline"
require_relative "net_http/failures"
require_relative "net_http/request_mapper"
require_relative "net_http/response_mapper"
require_relative "net_http/response_pump"
require_relative "net_http/tls_settings"
require_relative "net_http/proxy_route"
require_relative "net_http/adapter"

module Dexpace
  # Transport adapters: the synchronous and asynchronous transport seams' shipped
  # implementations. The seam contracts themselves live in dexpace-core.
  module Transport
    # The reference synchronous transport, over Ruby's `net/http` default gem (phase 8a). One
    # `Net::HTTP` per call, built from the request's own URL, with `max_retries = 0` and
    # `proxy_from_env = false` as the two one-line disables the SDK's own retry and proxy layers
    # need; the response body streams through a per-response producer thread (P8-1) and the
    # caller owns closing it. Two constructions, and ownership is decided at construction: `.build`
    # is the SDK-managed one, `.using` wraps a caller's own client verbatim (P8-15).
    #
    # What the wire carries (R2): the caller's headers minus MANAGED_HEADERS, plus `Host` and the
    # framing header the transport derives, plus a `Content-Type` on every body-permitted method
    # (P8-4). `Accept`, `User-Agent` and `Accept-Encoding` are never invented (P8-2), and a
    # `Content-Encoding` response is delivered exactly as the server sent it -- compressed, with
    # its headers intact -- because `decode_content` is off (P8-3); a caller who wants compression
    # sets `Accept-Encoding` and decodes.
    module NetHTTP
      extend self

      # The configured tier's fallback for RequestOptions#timeout (R3): the total per-call budget
      # when neither the call nor the transport nor Configuration::Keys::REQUEST_TIMEOUT says
      # otherwise. A named setting, not a literal at the call site.
      DEFAULT_TIMEOUT_SECONDS = 60.0

      # TRANSPORT-6's clamp floor. net-http's three timeout knobs accept floats down to 0.0005 and
      # treat zero as "poll once", so a strictly positive remaining budget below this is clamped
      # UP to it rather than handed over as a near-zero that would time out from a confusing place.
      MIN_TIMEOUT_SECONDS = 0.001

      # The bounded join on a response's producer thread when the response is closed (XCUT-13,
      # TRANSPORT-16): never `Thread#join` with no argument.
      JOIN_DEADLINE_SECONDS = 5.0

      # The key the require-time registration below uses, and the key a caller passes to
      # Dexpace::Transport when they want this adapter by name.
      REGISTRY_KEY = :net_http

      # R18: the keys `.build`'s `tls:` accepts, and nothing else -- an unknown key raises, because
      # a silently ignored `verify_mode:` is a security setting the caller believes they set. The
      # values are plain (a path String, an OpenSSL object the caller built, a Symbol version), so
      # no OpenSSL constant reaches a public signature (NFR-11).
      TLS_SETTINGS = %i[ca_file ca_path cert key verify_mode min_version].freeze

      # TRANSPORT-11's drop set (P8-13): the requirement's named minimum -- host, content-length,
      # transfer-encoding -- plus seven RFC 9110 §7.6.1 hop-by-hop names the requirement's own text
      # invites. Folded, because HeaderName#folded is what every lookup compares against. Two carry
      # their own reason: `expect`, because Net::HTTP#continue_timeout is nil by default so
      # `Expect: 100-continue` would hang against a server that waits; and `connection`, because
      # this adapter builds and closes a client per call. `proxy-authorization` is deliberately
      # NOT here: this adapter stamps no proxy credential of its own, so a caller-set value passes
      # through like any other header. Ten names, a shared transport contract with the async
      # adapter, which drops the same ten under its own constant (NFR-2 forbids sharing the
      # constant itself).
      MANAGED_HEADERS = %w[
        host content-length transfer-encoding connection keep-alive proxy-connection te trailer
        upgrade expect
      ].freeze

      # P8-4: the Content-Type a body-permitted request carries when neither the caller's headers
      # nor the body's own media type supplies one -- RFC 9110's own default for a payload of
      # unknown type, and the one value that claims nothing about the bytes. Net::HTTP's own
      # fallback would be `application/x-www-form-urlencoded`, a claim a server acts on.
      DEFAULT_CONTENT_TYPE = "application/octet-stream"

      # TRANSPORT-30's SHOULD: the WARNING event emitted once per call when a resolved proxy
      # carries something Net::HTTP cannot honour -- a custom challenge handler, or a SOCKS type
      # -- before the adapter proceeds with Basic from the proxy's username and password. Named
      # here rather than in core's Events because nothing outside this gem reads it.
      PROXY_LIMITATION_EVENT = "http.transport.proxy_limitation"

      # The SDK-managed construction. Every call builds its own `Net::HTTP` from the request's
      # URL (TRANSPORT-29: nothing is shared between calls), applies this call's total budget to
      # the three timeout knobs (R3), and closes the connection when the response is closed.
      #
      # The budget's three tiers, highest first: `RequestOptions#timeout` on the call, `timeout:`
      # here, then `Configuration::Keys::REQUEST_TIMEOUT` -- read through `Configuration#duration`,
      # whose grammar treats a BARE number as milliseconds (CFG-7): `REQUEST_TIMEOUT=30` is thirty
      # milliseconds, and thirty seconds is `30s` or `PT30S` -- and finally
      # DEFAULT_TIMEOUT_SECONDS.
      #
      # `tls:` is applied only to an `https` request and only for the keys given (R18): `ca_file`
      # and `ca_path` are path Strings, `cert` an OpenSSL::X509::Certificate and `key` an
      # OpenSSL::PKey the caller built, `verify_mode` an Integer such as
      # OpenSSL::SSL::VERIFY_PEER, `min_version` a Symbol such as `:TLS1_2`. With no `tls:` nothing
      # is assigned and OpenSSL's own defaults -- VERIFY_PEER with hostname verification -- apply.
      # Passing `verify_mode: OpenSSL::SSL::VERIFY_NONE` is the caller disabling verification
      # deliberately; the adapter never weakens a default on its own.
      #
      # @param timeout [Numeric, nil] the per-transport default budget in seconds; nil defers to
      #   the configuration chain
      # @param logger [Dexpace::Instrumentation::Logger] where header drops and proxy limitations
      #   are logged; defaults to the null logger so no caller holds a nil
      # @param tls [Hash, nil] the TLS settings, keyed by TLS_SETTINGS
      # @return [Adapter] an owning adapter (`#owned?` is true)
      # @raise [Dexpace::InvalidArgumentError] for a `tls:` that is not a Hash or names an
      #   unknown key
      def build(timeout: nil, logger: ::Dexpace::Instrumentation::Logger::NULL, tls: nil)
        Adapter.owning(timeout: timeout, logger: logger, tls: TLSSettings.validate!(tls))
      end

      # The borrowing construction (P8-15): the caller's `Net::HTTP` is used verbatim -- no knob,
      # no endpoint and no `use_ssl` is ever assigned on it, and it is neither started nor
      # finished by the adapter, so a client the caller already started keeps its connection. The
      # consequences are the contract: the endpoint is the client's, and a request naming a
      # different host, port or scheme is refused; a per-call `RequestOptions#timeout` is refused
      # rather than applied to someone else's client (P8-6); and calls are serialised, one
      # exchange at a time from `#call` until its response is closed, because one `Net::HTTP`
      # cannot carry two exchanges at once.
      #
      # @param client [Net::HTTP] the caller's own client, which must already have
      #   `max_retries == 0` -- the adapter asserts it rather than setting it, because
      #   TRANSPORT-2 scopes the disable to an SDK-managed transport and XCUT-22 forbids mutating
      #   a caller's object (P8-10)
      # @param logger [Dexpace::Instrumentation::Logger] as for `.build`
      # @return [Adapter] a borrowing adapter (`#owned?` is false)
      # @raise [Dexpace::InvalidArgumentError] when the client's `max_retries` is not zero
      def using(client, logger: ::Dexpace::Instrumentation::Logger::NULL)
        Adapter.borrowing(client, logger: logger)
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
      # Dexpace::VERSION mismatch (design §2.4).
      ::Dexpace::Transport.register(
        REGISTRY_KEY, method(:default),
        core: "~> #{::Dexpace::VERSION.split(".").first(2).join(".")}",
      )
    end
  end
end
