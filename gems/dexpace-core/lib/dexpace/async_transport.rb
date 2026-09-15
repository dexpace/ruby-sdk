# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "registry"
require_relative "async/future"
require_relative "bridge/sync_over"
require_relative "error/seam_error"
require_relative "error/invalid_argument_error"

module Dexpace
  # The asynchronous transport seam: any object responding to
  # #call(request, options, cancellation) and returning a Dexpace::Async::Future.
  #
  # A second top-level constant and a second registry rather than a namespace under
  # Dexpace::Transport (deviation P2-1). SEAM-2 enumerates the two transports as two seams, and
  # Dexpace::Transport::Async would sit beside Dexpace::Transport::NetHTTP and ::AsyncHTTP -- two
  # adapter namespaces -- which is the confusion SEAM-2 exists to prevent.
  #
  # The seam's return type is the core-owned pivot (design §10.3), never a third-party future, so
  # NFR-11's scan over sig/ stays satisfiable; phase 8's adapters bridge to it and never replace it.
  module AsyncTransport
    REGISTRY = Registry.new(
      seam: "async transport",
      installer: "Dexpace::AsyncTransport.install",
      conforms: ->(object) { Dexpace::AsyncTransport.conforms?(object) },
    )
    private_constant :REGISTRY

    class << self
      # The same predicate as the synchronous seam's: the two seams differ only in return type,
      # which no runtime check can see before the first call (the gap Dexpace::Transport records).
      def conforms?(object) = Dexpace::Registry.callable?(object, arity: 3)

      # Require-time self-registration (design §3.6), with the version-skew guard on `core:`.
      def register(key, factory, core:)
        REGISTRY.register(key, factory, core: core)
        self
      end

      # SEAM-5's explicit install, which always wins over a registered factory.
      def install(transport)
        REGISTRY.install(transport)
        self
      end

      # The resolved async transport (SEAM-5, SEAM-7).
      def resolve = REGISTRY.resolve

      # The keys every required adapter registered under.
      def registered_keys = REGISTRY.registered_keys

      # SEAM-6's test-scoped override: block-scoped, unchecked, restored afterwards.
      def swap(transport, &) = REGISTRY.swap(transport, &)

      # SEAM-18's async-to-sync bridge.
      def sync_over(transport)
        unless conforms?(transport)
          raise Dexpace::InvalidArgumentError,
                "an async transport responds to #call(request, options, cancellation) and " \
                "returns a Dexpace::Async::Future; #{transport.class} does not"
        end

        Dexpace::Bridge::SyncOver.new(transport)
      end
    end
  end
end
