# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "registry"
require_relative "closeable"
require_relative "bridge/async_over"
require_relative "error/invalid_argument_error"

module Dexpace
  # The synchronous transport seam: a duck type, a .conforms? predicate, and an RBS interface in
  # sig/. There is no module to include and no class to inherit.
  #
  # A transport is any object responding to #call(request, options, cancellation) and returning a
  # Dexpace::Response. #call is the convergence point of Ruby's own middleware ecosystems (Rack,
  # Faraday adapters), so a bare lambda is a valid transport, phase 4's Dexpace::Pipeline can stand
  # in wherever a transport is expected (PIPE-26), and no adapter has to declare conformance it
  # structurally already has.
  #
  # SEAM-11's three clauses. *Single operation*: one #call, one response; there is no batch entry
  # point to add later. *No pre-buffering*: the returned response's body is a lazily-read stream the
  # caller owns and closes -- stated at the seam here, proved over a real socket in phase 8 and
  # asserted per adapter by dexpace-conformance (phase 8a's TransportSuite). *Options may be
  # ignored*: options are always passed and are always an immutable Dexpace::RequestOptions, so
  # "behaves identically" is structural rather than a discipline.
  #
  # SEAM-13's cancellation reaches a transport as the third argument -- an ordinary value, never an
  # ambient interrupt -- and a transport honours it by re-checking #cancelled? at every point it
  # resumes from a wait.
  #
  # SEAM-15 is a MAY -- "a port MAY choose a [post-close failure] mode but SHOULD document it" --
  # and the documented mode is narrower than "a send after close raises": **a transport that owns
  # the resource it closed raises Dexpace::ClosedError from a later send.** A wrapper that only
  # borrows closes nothing and stays usable, which is why both SEAM-18 bridges answer #close,
  # release nothing and keep working; raising there would break XCUT-22's "the caller owns its
  # lifecycle and may keep using it after the SDK component is closed". Phase 2 ships no owning
  # transport, so it ships the error class and the rule and no raise site -- phase 8's adapters are
  # the first owners, and dexpace-conformance is where the raise is asserted.
  #
  # One gap, admitted rather than papered over: the synchronous and asynchronous seams have the
  # same structural shape and differ only in return type, so .conforms? cannot tell an async
  # transport registered here from a sync one. They are two registries and an adapter names which
  # it registers into; dexpace-conformance asserts the return type. A predicate claiming to
  # distinguish them would be a false proof, which is the position design §10.10 takes on HTTP-2.
  module Transport
    REGISTRY = Registry.new(
      seam: "transport",
      installer: "Dexpace::Transport.install",
      conforms: ->(object) { Dexpace::Transport.conforms?(object) },
    )
    private_constant :REGISTRY

    class << self
      # The runtime half of the seam: any object callable with the three positional arguments.
      def conforms?(object) = Dexpace::Registry.callable?(object, arity: 3)

      # Require-time self-registration (design §3.6): `core:` is the adapter's `~> MAJOR.MINOR`
      # requirement on dexpace-core, checked here against Dexpace::VERSION.
      def register(key, factory, core:)
        REGISTRY.register(key, factory, core: core)
        self
      end

      # SEAM-5's explicit install, which always wins over a registered factory.
      def install(transport)
        REGISTRY.install(transport)
        self
      end

      # The resolved transport, built once from the sole registered factory when nothing was
      # installed (SEAM-5, SEAM-7).
      def resolve = REGISTRY.resolve

      # The keys every required adapter registered under.
      def registered_keys = REGISTRY.registered_keys

      # SEAM-6's test-scoped override: block-scoped, unchecked, restored afterwards.
      def swap(transport, &) = REGISTRY.swap(transport, &)

      # SEAM-18's sync-to-async bridge. The executor is required and has no default, because a
      # shared global pool would be starved by blocking work -- the requirement says so in as many
      # words. It is a duck type exposing #post { ... }; core ships no implementation, which is
      # SEAM-1 again, and phase 8's dexpace-async-thread supplies the first one.
      def async_over(transport, executor:)
        unless conforms?(transport)
          raise Dexpace::InvalidArgumentError,
                "a transport responds to #call(request, options, cancellation); " \
                "#{transport.class} does not"
        end
        unless executor.respond_to?(:post)
          raise Dexpace::InvalidArgumentError,
                "async_over requires an executor responding to #post; there is intentionally " \
                "no default, because a shared global pool would be starved by blocking work"
        end

        Dexpace::Bridge::AsyncOver.new(transport, executor)
      end
    end
  end
end
