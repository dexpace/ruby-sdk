# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "vacuous"

module Dexpace
  module Conformance
    # What an InvariantSuite assertion receives.
    #
    # `core` is the loaded Dexpace module -- XCUT's subjects are core constants, not an instance.
    # Everything else is a factory the DRIVER supplies, because the suite can reach none of them
    # itself: `Dexpace::BoundedMap` is a `private_constant`, 6c's cnonce is drawn inside
    # `#authorization_for`, and building a redirect hop needs a pipeline cursor and a scripted 3xx.
    #
    # `mutable` is the driver's declaration of which instance variables on a shared instance are a
    # mutex with the state it guards or Closeable's latch (design P9-9): never read off the audited
    # object, which could then exempt the per-call state XCUT-11 forbids.
    class InvariantCase
      # @return [Module] the loaded core module under audit
      attr_reader :core
      # @return [Array<Symbol>] the driver's declared-mutable ivars for XCUT-11
      attr_reader :mutable

      def initialize(core:, seam: nil, transport: nil, mutable: [], shared: [], bounded_map: nil,
                     bounded_map_store: nil, cnonce: nil, redirect_hops: nil, credential_hop: nil)
        @core = core
        @seam = seam
        @transport = transport
        @mutable = mutable
        @shared = shared
        @bounded_map = bounded_map
        @bounded_map_store = bounded_map_store
        @cnonce = cnonce
        @redirect_hops = redirect_hops
        @credential_hop = credential_hop
      end

      # Every shared instance the driver declares, as `[label, object, declared_ivars]`. Design R8
      # names NINE across five phase documents; the suite audits each through SharedInstance and
      # cannot reach one of them by itself, because "which ivar is the mutex" is the driver's
      # knowledge and not the audited object's (P9-9).
      #
      # @return [Array<Array(String, Object, Array<Symbol>)>]
      def shared_instances
        @shared
      end

      # Design R3: every audit opens with an existence probe against the name the owning phase
      # committed to, and an ABSENT artifact is :vacuous NAMING WHO PROMISED IT -- not :failed.
      # Phase 9 was planned before any code existed, so reporting :failed would conflate "not
      # built" with "built wrong", which is the distinction phase 10 acts on. Nothing passes by not
      # being built: an un-waived MUST-level vacuity is a report blocker
      # (Report#blocking_vacuities).
      #
      # @param name [Symbol] the constant or method name promised
      # @param promised_by [String] the phase and artifact that promised it
      # @param method [Boolean] probe `#respond_to?` rather than `#const_defined?`
      # @return [nil]
      # @raise [Vacuous] when the artifact is absent
      def probe!(name, promised_by, method: false)
        present = method ? @core.respond_to?(name) : @core.const_defined?(name)
        return nil if present

        raise Vacuous, "#{name} is absent; #{promised_by} committed to it"
      end

      # @return [Boolean] whether the driver supplied a seam factory
      def seam? = !@seam.nil?

      # The seam under audit: a closeable component the driver builds. `client:` is the ONE setting
      # the suite passes -- XCUT-22 needs a caller-supplied resource and nothing else does -- and it
      # is a named keyword rather than a splat, because `Dexpace/NoKeywordSplat` refuses one in any
      # gem's lib/ and 8a's TransportCase#transport already names its two.
      #
      # @param client [Object, nil] a caller-supplied resource the seam must not close
      def seam(client: nil)
        factory = required!(@seam, "no seam implementation supplied to InvariantSuite.run")
        factory.call(client: client)
      end

      # @return [Boolean] whether the driver supplied a transport factory
      def transport? = !@transport.nil?

      # A transport factory, for the one assertion whose subject is an adapter's dispatch path
      # (XCUT-18's second assertion, the wire-boundary re-validation phase 1 named for this phase).
      # Kept apart from `seam` because a driver may supply both and they are different objects.
      def transport
        required!(@transport, "no transport factory supplied to InvariantSuite.run").call
      end

      # Dexpace::BoundedMap is a private_constant of Dexpace (4a's P4-3), reachable by its BARE name
      # from a full-nesting body and by `Dexpace.const_get` -- but not by the scoped spelling. The
      # factory route keeps the suite out of that question entirely: the driver is core's own suite
      # and knows what to build.
      def bounded_map(cap:)
        required!(@bounded_map, "no bounded-map factory supplied to InvariantSuite.run")
          .call(cap: cap)
      end

      # XCUT-14's drain clause needs the map's backing Hash, which BoundedMap keeps private. The
      # driver knows that name and hands in a reader; the suite never reaches into the object.
      def bounded_map_store(map)
        required!(@bounded_map_store, "no bounded-map store reader supplied to InvariantSuite.run")
          .call(map)
      end

      # @return [Boolean] whether the driver supplied a cnonce driver
      def cnonce? = !@cnonce.nil?

      # 6c's DigestHandler takes `cnonce_source:` and calls `#hex(16)` on it inside
      # `#authorization_for`; the driver knows how to build one with a credential and a challenge,
      # and the assertion needs only the rendered value back.
      def draw_cnonce(source)
        required!(@cnonce, "no cnonce driver supplied to InvariantSuite.run").call(source)
      end

      # XCUT-17 needs one redirect re-issue driven through 6b's step. Building the step, its cursor
      # and the scripted 3xx is the driver's job; the assertion needs only the re-issued request
      # back -- anything answering `#headers` (with `#[]`) and `#url` -- or the error a refusal
      # raises.
      def redirect_hop(from:, to:, headers:)
        required!(@redirect_hops, "no redirect driver supplied to InvariantSuite.run")
          .call(from: from, to: to, headers: headers)
      end

      # XCUT-16 needs one drive of the credential-attaching path. Building 6c's step, its stamper
      # and a cursor carrying 6b's cross-origin marker is the driver's job; the assertion needs
      # only the request that went out -- anything answering `#headers` with `#[]` -- or the error
      # the HTTPS guard raised.
      #
      # @param url [String] the request target
      # @param cross_origin [Boolean] the REDIRECT pillar's marker, which suppresses the stamp
      def credential_hop(url:, cross_origin: false)
        required!(@credential_hop, "no credential driver supplied to InvariantSuite.run")
          .call(url: url, cross_origin: cross_origin)
      end

      private

      def required!(factory, reason)
        raise Vacuous, reason if factory.nil?

        factory
      end
    end
  end
end
