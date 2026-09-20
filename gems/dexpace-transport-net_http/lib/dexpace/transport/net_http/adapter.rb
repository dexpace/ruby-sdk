# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module NetHTTP
      # The transport (SEAM-11). Two named entry points make ownership a construction-time fact
      # (design §3.7), which is what SEAM-15's documented post-close mode keys off: an owning
      # adapter raises Dexpace::ClosedError on a send after `#close`, a borrowing one closes
      # nothing and stays usable, because the client is the caller's (XCUT-22). Frozen in effect
      # after construction -- the only state an instance ever writes is Closeable's latch -- which
      # is what TRANSPORT-29's "effectively immutable after construction" means in Ruby; every
      # per-call object lives in `#call`'s own frame or in the returned response graph.
      #
      # The transport's own `#close` cancels no in-flight response: each response's pump is owned
      # by the Dexpace::Response that holds it (SEAM-25).
      class Adapter # rubocop:disable Metrics/ClassLength -- one seam over two constructions: ownership is a fact of one object (design §3.7), so the owning and the borrowing paths are one class and split by nothing but method
        include ::Dexpace::Closeable

        private_class_method :new

        # The SDK-managed construction behind NetHTTP.build, which is the entry point a caller
        # uses; public because the module function calls it with an explicit receiver.
        #
        # @api private
        # @return [Adapter]
        def self.owning(timeout:, logger:, tls:)
          timeout!(timeout)
          new(client: nil, timeout: timeout, logger: logger, tls: tls, owned: true)
        end

        # The borrowing construction behind NetHTTP.using: refuses the client here (P8-10),
        # before an instance exists.
        #
        # @api private
        # @return [Adapter]
        def self.borrowing(client, logger:)
          unless client.respond_to?(:max_retries) && client.max_retries.zero?
            raise ::Dexpace::InvalidArgumentError,
                  "a borrowed Net::HTTP must already have max_retries == 0 (TRANSPORT-2): the " \
                  "adapter may not set it on a client it does not own (XCUT-22)"
          end

          new(client: client, timeout: nil, logger: logger, tls: nil, owned: false)
        end

        def self.timeout!(timeout)
          return if timeout.nil?
          return if timeout.is_a?(::Numeric) && timeout.finite? && timeout.positive?

          raise ::Dexpace::InvalidArgumentError,
                "timeout must be a finite, positive number of seconds or nil, got " \
                "#{timeout.inspect}"
        end
        private_class_method :timeout!

        def initialize(client:, timeout:, logger:, tls:, owned:)
          @client = client
          @timeout = timeout
          @logger = logger
          @tls = tls
          @clock = ::Dexpace::Clock::SYSTEM
          # P8-15: one permit, so calls through a BORROWED client are serialised for the whole
          # life of each exchange. A SizedQueue and not a Mutex: the permit is returned by the
          # response pump's producer, on its own thread, and Mutex#unlock from a non-owner raises.
          @permit = owned ? nil : ::Thread::SizedQueue.new(1).tap { |queue| queue.push(:permit) }
          initialize_closeable(owned: owned)
        end

        # The seam: validates, maps, dispatches, adapts and returns a Dexpace::Response whose
        # body streams from the socket until the caller drains or closes it (SEAM-11,
        # TRANSPORT-25). Every failure that produced no response surfaces classified through
        # the cancellation token first (TRANSPORT-3) and as a retryable Dexpace::TransportError
        # otherwise (TRANSPORT-20); a Dexpace::Error of the SDK's own passes through unchanged.
        #
        # @param request [Dexpace::Request]
        # @param options [Dexpace::RequestOptions] `#timeout` is this call's TOTAL budget in
        #   seconds (R3); nil takes the transport's default
        # @param cancellation [Dexpace::Cancellation, nil] nil is the never-cancelled token
        # @return [Dexpace::Response]
        # @raise [Dexpace::ClosedError] on an owning adapter after `#close` (SEAM-15)
        # @raise [Dexpace::CancelledError] when the token is cancelled, before or during the call
        # @raise [Dexpace::TransportError] for any failure that produced no response
        # @raise [Dexpace::InvalidArgumentError] on a borrowing adapter for a per-call timeout
        #   (P8-6) or a request naming another origin (P8-15), and for a forged header (HTTP-17)
        def call(request, options, cancellation)
          perform(request, options, cancellation || ::Dexpace::Cancellation.none)
        end

        private

        def perform(request, options, cancellation)
          raise ::Dexpace::ClosedError, "this transport is closed" if closed? && owned?

          cancellation.check!
          if owned?
            owned_call(request, options, cancellation)
          else
            borrowed_call(request, options, cancellation)
          end
        rescue ::StandardError => error
          # Raised from inside the rescue, so Ruby's implicit #cause wiring attaches the original
          # for free; `cause: nil` is the OTHER case, a failure carried across a thread boundary,
          # and it is the pump's spelling and not this one's.
          raise Failures.wrap(error, phase: :connect, cancellation: cancellation)
        end

        # TRANSPORT-5 and TRANSPORT-6: a fresh Net::HTTP per call, built FROM THIS REQUEST'S URL
        # and with its three timeout knobs assigned from THIS call's own deadline -- never a
        # shared client, so "leaving the shared native client's configuration untouched" holds
        # by construction. An expired budget raises before the socket is touched.
        def owned_call(request, options, cancellation)
          deadline = Deadline.build(clock: @clock, budget: resolve_timeout(options))
          if deadline.expired?
            raise ::Dexpace::TransportError.new("the per-call budget expired before dispatch",
                                                phase: :connect,)
          end

          native = RequestMapper.build(request, logger: @logger)
          dispatch(request, native: native, http: owned_client_for(request.url, deadline),
                            deadline: deadline, cancellation: cancellation, owns_connection: true,
                            permit: nil,)
        end

        # R3's three tiers, highest first: the call, the transport, the configuration chain --
        # through Configuration#duration, whose bare-number grammar is milliseconds (CFG-7).
        def resolve_timeout(options)
          options.timeout || @timeout || configured_timeout
        end

        def configured_timeout
          key = ::Dexpace::Configuration::Keys::REQUEST_TIMEOUT
          ::Dexpace.configuration.duration(key, default: DEFAULT_TIMEOUT_SECONDS) ||
            DEFAULT_TIMEOUT_SECONDS
        end

        # The endpoint is a CONSTRUCTOR ARGUMENT and never an assignment: Net::HTTP declares
        # `address` and `port` as readers only. The four proxy positionals come from phase 5a's
        # resolver through ProxyRoute (R17), and an explicit nil there is what takes Net::HTTP's
        # `:ENV` default off the table; `proxy_from_env = false` says the same thing twice on
        # purpose. TLS settings are applied only when the URL is https (R18).
        def owned_client_for(url, deadline)
          http = routed_client(url)
          http.use_ssl = url.scheme == "https"
          TLSSettings.apply(http, @tls || {}) if http.use_ssl?
          apply_budget(http, deadline)
        end

        def routed_client(url)
          proxy = ProxyRoute.for(url, logger: @logger)
          http = ::Net::HTTP.new(url.hostname.to_s, url.port, proxy.address, proxy.port,
                                 proxy.username, proxy.password,)
          http.proxy_from_env = false
          http.max_retries = 0 # TRANSPORT-2: the SDK's retry layer is the only retry
          http
        end

        def apply_budget(http, deadline)
          budget = deadline.clamped
          http.open_timeout = budget
          http.write_timeout = budget
          http.read_timeout = budget
          http
        end

        # P8-15: the borrowed client is used VERBATIM, so the endpoint is the CLIENT's and a
        # request naming a different one is refused rather than sent somewhere the caller's
        # Request does not name; P8-6: a non-nil per-call timeout is refused, and the OPTIONS
        # value is checked rather than the resolved one, because a configured default must not
        # be silently applied to someone else's client either. The native request is mapped
        # BEFORE the permit is taken, so a refused header holds nothing up; from the moment the
        # pump exists, its producer returns the permit.
        def borrowed_call(request, options, cancellation)
          unless options.timeout.nil?
            raise ::Dexpace::InvalidArgumentError,
                  "a per-call timeout cannot apply to a borrowed Net::HTTP without mutating it " \
                  "(TRANSPORT-5 against XCUT-22); use NetHTTP.build for a call that needs one"
          end
          check_endpoint!(request.url)

          native = RequestMapper.build(request, logger: @logger)
          permit = @permit
          permit&.pop
          dispatch(request, native: native, http: @client, deadline: nil,
                            cancellation: cancellation, owns_connection: false, permit: permit,)
        end

        def check_endpoint!(url)
          return if bound_to?(url)

          raise ::Dexpace::InvalidArgumentError,
                "a borrowed Net::HTTP is bound to #{@client.address}:#{@client.port} " \
                "(use_ssl=#{@client.use_ssl?}) and this request names " \
                "#{url.hostname}:#{url.port} (use_ssl=#{url.scheme == "https"}); the adapter " \
                "may not re-point a client it does not own (TRANSPORT-15, XCUT-22): use " \
                "NetHTTP.build, or a client bound to this origin"
        end

        def bound_to?(url)
          url.hostname.to_s.downcase == @client.address.to_s.downcase &&
            url.port == @client.port && (url.scheme == "https") == @client.use_ssl?
        end

        # The head is adapted on THIS thread, so every Dexpace object in the returned graph is
        # built where the caller can see a failure; if adaptation raises, the pump is closed
        # before the error propagates (TRANSPORT-22), which is the connection's release. The
        # permit goes back here only when the pump could not be constructed at all; once its
        # producer thread exists, that thread's own ensure returns it.
        def dispatch(request, native:, http:, deadline:, cancellation:, owns_connection:, permit:)
          pump = begin
            ResponsePump.new(http: http, native: native, deadline: deadline,
                             cancellation: cancellation, owns_connection: owns_connection,
                             permit: permit,)
          rescue ::StandardError
            permit&.push(:permit)
            raise
          end
          pump.head_or_raise do |head|
            ResponseMapper.build(request: request, native: head, pump: pump, logger: @logger,
                                 head: request.method.token == "HEAD",)
          end
        rescue ::StandardError
          ::Dexpace.close_quietly(pump)
          raise
        end

        # The managed construction owns no long-lived native resource, so there is nothing to
        # release; the borrowing construction never reaches here, because Closeable#close skips
        # #release when `owned?` is false.
        def release
          nil
        end
      end
    end
  end
end
