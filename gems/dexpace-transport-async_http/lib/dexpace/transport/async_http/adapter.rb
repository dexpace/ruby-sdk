# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # The Dexpace::AsyncTransport seam implementation (SEAM-16). `#call` returns a
      # Dexpace::Async::Future before doing anything fallible, and nothing between minting the
      # pivot and settling it raises to the caller: a pre-dispatch failure -- a forged header the
      # wire-boundary re-validation refuses, a URL this transport cannot dispatch, a call with no
      # reactor -- is delivered through the future (TRANSPORT-21), and only `Async::Cancel`,
      # NoMemoryError, SystemExit, SignalException and Interrupt may propagate synchronously, which
      # `rescue ::StandardError` excludes without a hand-written list.
      #
      # Two named entry points make ownership a construction-time fact (design §3.7): an owning
      # adapter builds one `Async::HTTP::Client` per (reactor, origin) and closes them all; a
      # borrowing one carries every request through the caller's client and never closes it
      # (TRANSPORT-15, XCUT-22). Frozen in effect after construction -- the only writes are the
      # client map's own and Closeable's latch, each under its own mutex -- and every per-call
      # value lives on the Exchange and its Completer (TRANSPORT-29, ASYNC-22).
      #
      # The adapter creates no reactor (P8-39): `Sync {}` would block the caller's thread and
      # defeat the seam, and an owned reactor thread is a thread pool by another name and a
      # long-lived fiber carrying the constructor's diagnostic context rather than the caller's.
      # A call from a thread with no `Fiber.scheduler` settles Dexpace::SeamError naming the fix.
      class Adapter
        include ::Dexpace::Closeable

        # What a call outside a reactor settles with.
        REACTOR_MESSAGE = "Dexpace::Transport::AsyncHTTP requires a running Async reactor on " \
                          "the calling thread; wrap the call in `Sync { }` or `Async { }`"

        private_class_method :new

        # The SDK-managed construction behind AsyncHTTP.build, which is the entry point a caller
        # uses; public because the module function calls it with an explicit receiver.
        #
        # @api private
        # @return [Adapter]
        def self.owning(timeout:, logger:, drop_policy:, connection_limit:, ssl_context:,
                        configuration:)
          timeout!(timeout)
          configuration ||= ::Dexpace.configuration
          clients = Clients.build(configuration: configuration, connection_limit: connection_limit,
                                  ssl_context: ssl_context,)
          new(clients: clients, client: nil, timeout: timeout, logger: logger,
              drop_policy: drop_policy, configuration: configuration, owned: true,)
        end

        # The borrowing construction behind AsyncHTTP.using: refuses the client here, before an
        # instance exists.
        #
        # @api private
        # @return [Adapter]
        def self.borrowing(client, logger:, drop_policy:)
          unless client.respond_to?(:call) && client.respond_to?(:retries) && client.retries.zero?
            raise ::Dexpace::InvalidArgumentError,
                  "a borrowed Async::HTTP::Client must already have retries == 0 (TRANSPORT-2): " \
                  "the adapter may not set it on a client it does not own (XCUT-22)"
          end

          new(clients: nil, client: client, timeout: nil, logger: logger,
              drop_policy: drop_policy, configuration: ::Dexpace.configuration, owned: false,)
        end

        def self.timeout!(timeout)
          return if timeout.nil?
          return if timeout.is_a?(::Numeric) && timeout.finite? && timeout.positive?

          raise ::Dexpace::InvalidArgumentError,
                "timeout must be a finite, positive number of seconds or nil, got " \
                "#{timeout.inspect}"
        end
        private_class_method :timeout!

        def initialize(clients:, client:, timeout:, logger:, drop_policy:, configuration:, owned:)
          @clients = clients
          @client = client
          @timeout = timeout
          @logger = logger
          @drop_policy = drop_policy || DropPolicy.build
          @configuration = configuration
          initialize_closeable(owned: owned)
        end

        # The seam: mints the pivot, refuses what must be refused through it, maps the request on
        # the caller's own fiber, and hands the exchange to a child task of the caller's.
        #
        # @param request [Dexpace::Request]
        # @param options [Dexpace::RequestOptions, nil] `#timeout` is this call's budget up to the
        #   response head, in seconds; nil takes the transport's default
        # @param cancellation [Dexpace::Cancellation, nil] nil is the never-cancelled token
        # @return [Dexpace::Async::Future] settled with a Dexpace::Response, failed with a
        #   Dexpace::TransportError (retryable), a Dexpace::InvalidArgumentError, a
        #   Dexpace::ClosedError or a Dexpace::SeamError, or cancelled with Dexpace::CancelledError
        def call(request, options, cancellation)
          cancellation ||= ::Dexpace::Cancellation.none
          completer = ::Dexpace::Async::Completer.new
          dispatch(completer, request, options, cancellation)
          completer.future
        end

        private

        # Steps 2 to 10, on the caller's fiber. The post-close guard settles through the future,
        # because SEAM-15's "a send after close raises" names the sync seam's channel and
        # TRANSPORT-21 governs this one; a borrowing adapter stays usable after its own close, as
        # dexpace-transport-net_http's does, because the client is the caller's.
        def dispatch(completer, request, options, cancellation)
          if closed? && owned?
            return completer.fail(::Dexpace::ClosedError.new("this transport is closed"))
          end

          task = ::Async::Task.current?
          return completer.fail(::Dexpace::SeamError.new(REACTOR_MESSAGE)) if task.nil?

          cancellation.check!
          exchange_for(completer, request, options, cancellation).start(task)
        rescue ::StandardError => error
          # Errors.settle, never a bare #fail: Endpoints and OpenSSL raise ArgumentError,
          # OpenSSL::X509::StoreError and Errno::* here -- none a Dexpace:: error -- and P6-4's
          # obligation is "wrap, and default to retryable" at every site; a Dexpace:: error, the
          # re-validation's InvalidArgumentError included, passes through unchanged, and a
          # cancelled token -- `check!`'s raise, or a cancel racing the mapping -- settles a
          # cancellation, never a failure carrying one.
          Errors.settle(completer, error, phase: :connect, cancellation: cancellation)
        end

        # The three tiers, highest first: the call, the transport, then the configuration chain
        # through Configuration#duration, whose bare-number grammar is milliseconds (CFG-7).
        # Steps 4 to 7: the native request (the re-validation and the header drops happen inside
        # the mapping), the client for this origin under the calling fiber's reactor, and this
        # call's budget.
        def exchange_for(completer, request, options, cancellation)
          Exchange.new(
            completer: completer, cancellation: cancellation, request: request,
            native_request: RequestMapper.call(request, logger: @logger, drop_policy: @drop_policy),
            client: client_for(request.url, ::Fiber.scheduler), deadline: resolve_timeout(options),
            logger: @logger,
          )
        end

        def resolve_timeout(options)
          options&.timeout || @timeout || configured_timeout
        end

        def configured_timeout
          key = ::Dexpace::Configuration::Keys::REQUEST_TIMEOUT
          @configuration.duration(key, default: DEFAULT_TIMEOUT_SECONDS) || DEFAULT_TIMEOUT_SECONDS
        end

        def client_for(url, reactor)
          clients = @clients
          return @client if clients.nil?

          clients.fetch(url, reactor: reactor)
        end

        # The owning construction releases every client it built, without waiting on any of
        # them (P8-37); the borrowing one never reaches here, because Closeable#close skips
        # #release when `owned?` is false.
        def release
          @clients&.close
          nil
        end
      end
    end
  end
end
