# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "vacuous"
require_relative "borrowed_pair"
require_relative "scripts"
require_relative "wire_server"

module Dexpace
  module Conformance
    # What an assertion body receives. #transport and #borrowed_transport track every transport
    # they build so #teardown -- driven by the runner, never by the assertion -- closes all of them;
    # #wire is lazy and memoized per case, because not every assertion needs a socket. The two
    # driver-supplied primitives, `settle:` and `wire:`, are the suite contract's clauses 8 and 11
    # (8a's R16): both default to the synchronous, TCPServer-backed shape, so a sync adapter's
    # driver passes neither and an async adapter's driver passes both without either forking an
    # assertion.
    class TransportCase
      # Clause 8's default send: `transport.call(request, options, cancellation)`, the sync seam.
      DEFAULT_SETTLE = lambda do |transport, request, options, cancellation|
        transport.call(request, options, cancellation)
      end

      # Clause 11's default fixture: a WireServer on the given script.
      DEFAULT_WIRE = ->(script) { WireServer.start(script) }

      # @param build [#call] a keyword-taking factory building the SDK-managed transport
      # @param borrow [#call, nil] a one-argument factory (the fixture's port) returning a
      #   BorrowedPair, or nil when the adapter has no borrowing construction
      # @param settle [#call] the send primitive, `(transport, request, options, cancellation)`
      # @param wire [#call] the fixture factory, taking a script
      def initialize(build:, borrow: nil, settle: DEFAULT_SETTLE, wire: DEFAULT_WIRE)
        @build = build
        @borrow = borrow
        @settle = settle
        @wire_factory = wire
        @transports = []
        @wire = nil
      end

      # A fresh SDK-managed transport from the driver's factory, passing only the settings given
      # -- the two the suite contract allows, `timeout:` and `logger:` (clause 4) -- behind the
      # clause-8 guard, so what an assertion receives cannot be #call-ed. The default #settle IS
      # transport.call, so an assertion that called #call directly would pass every run this
      # phase performs and fail only once an async driver replaces #settle; the guard makes that a
      # red test here instead.
      #
      # @param timeout [Numeric, nil] the transport-level default timeout, when an assertion sets it
      # @param logger [Object, nil] a Dexpace::Instrumentation::Logger, when the assertion passes it
      # @return [Object] the guarded transport
      def transport(timeout: nil, logger: nil)
        settings = {} #: Hash[Symbol, untyped]
        settings[:timeout] = timeout unless timeout.nil?
        settings[:logger] = logger unless logger.nil?
        SettleOnly.new(track(@build.call(**settings)))
      end

      # Clause 8: the ONE send primitive. An assertion calls this and never transport.call, so the
      # same body drives a sync transport and an async one whose future the driver awaits; clause 5
      # is that a cancellation surfaces from here as Dexpace::CancelledError on both paths.
      #
      # @param transport [Object] the guarded transport #transport or #borrowed_transport returned
      # @param request [Dexpace::Request]
      # @param options [Dexpace::RequestOptions]
      # @param cancellation [Dexpace::Cancellation]
      # @return [Dexpace::Response]
      def settle(transport, request, options = Dexpace::RequestOptions::EMPTY,
                 cancellation = Dexpace::Cancellation.none)
        @settle.call(SettleOnly.unwrap(transport), request, options, cancellation)
      end

      # Suite contract 4a: the driver's borrow factory takes the fixture's PORT and returns a
      # BorrowedPair, because the caller's own client is an adapter-specific object and an
      # assertion that constructed one would have parameterised itself on which adapter it is
      # looking at -- the one thing this gem may never contain. An adapter with no borrowing
      # construction supplies no factory, and the assertion is vacuous rather than failed.
      #
      # @return [BorrowedPair] the pair, its transport guarded like #transport's
      # @raise [Vacuous] when the driver supplied no `borrow:`
      def borrowed_transport
        if @borrow.nil?
          raise Vacuous, "this adapter's suite call supplied no borrowing construction " \
                         "(TRANSPORT-15's borrowed half)"
        end

        pair = @borrow.call(wire.port)
        track(pair.transport)
        BorrowedPair.build(transport: SettleOnly.new(pair.transport), probe: pair.probe)
      end

      # Clause 11: the fixture, from the driver's factory, started on the first call with the
      # script given then and returned as it is afterwards. Whatever the factory returns must
      # answer #port, #requests, #connections, #closed_connections and #await_closed_connection --
      # WireServer's own surface, which is therefore the contract (sig/'s `_Wire`).
      #
      # @param script [#call] the response script, used only on the first call
      # @return [Object] the fixture
      def wire(script: Scripts.fixed(""))
        @wire ||= @wire_factory.call(script)
      end

      # A request against the live fixture's own port -- which is also why the borrow factory
      # takes that port: a borrowing transport is bound to one origin (P8-15) and every request
      # the suite builds names this one.
      #
      # @param path [String] the request target
      # @param method [String] the method token
      # @param headers [Dexpace::Headers]
      # @param body [Dexpace::Body, nil]
      # @return [Dexpace::Request]
      def request(path: "/", method: "GET", headers: Dexpace::Headers::EMPTY, body: nil)
        Dexpace::Request.build(method: method, url: "http://127.0.0.1:#{wire.port}#{path}",
                               headers: headers, body: body,)
      end

      # Closes every transport this case built and the fixture, quietly, in that order. The
      # runner calls it in an ensure; an assertion never does.
      #
      # @return [nil]
      def teardown
        @transports.each { |transport| Dexpace.close_quietly(transport) }
        Dexpace.close_quietly(@wire)
        nil
      end

      private

      def track(built)
        @transports << built
        built
      end

      # Clause 8's guard: delegates every message but #call, on which it raises. Not a Data: it
      # wraps a foreign object and its identity is the subject's.
      class SettleOnly
        # @param object [Object] a guard or anything else
        # @return [Object] the guarded subject, or the object itself
        def self.unwrap(object)
          object.is_a?(SettleOnly) ? object.__subject__ : object
        end

        def initialize(subject)
          @subject = subject
        end

        # The wrapped transport, for #unwrap; double-underscored so no transport's own message
        # collides with it.
        def __subject__
          @subject
        end

        # Always raises: an assertion sends through TransportCase#settle and never through #call.
        def call(*)
          raise ::ArgumentError,
                "a conformance assertion must send through kase.settle(transport, request, " \
                "options, cancellation), never transport.call -- an async driver replaces " \
                "#settle with `transport.call(...).value(cancellation:)`, and a direct #call " \
                "returns a " \
                "Dexpace::Async::Future there (suite contract clause 8)"
        end

        def respond_to_missing?(name, include_private = false)
          @subject.respond_to?(name, include_private) || super
        end

        private

        def method_missing(name, ...)
          return super unless @subject.respond_to?(name)

          @subject.public_send(name, ...)
        end
      end
      private_constant :SettleOnly
    end
  end
end
