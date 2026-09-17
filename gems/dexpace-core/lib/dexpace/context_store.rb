# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "bounded_map"
require_relative "error/context_conflict_error"

module Dexpace
  # The process-wide registry of in-flight execution contexts, keyed by call key: CTX-7 through
  # CTX-13, CTX-18 and CTX-19.
  #
  # HAS a BoundedMap rather than BEING one, so CTX-8's and CTX-18's two-operation surface is what
  # a caller sees and the map's general operations are not part of it. #set and #put take a
  # CONTEXT, not a key/value pair, and read #call_key off it: that is the narrowest duck type the
  # operation actually uses (api-design/88e6bf12), it makes CTX-3's "all three flavors register
  # under the identical store slot" unforgeable at the call site, and it is what lets the suite
  # drive every store rule with a two-member fake.
  #
  # Nothing in core reads a context back out of this store: promotion writes and returns, #close
  # conditionally removes and tolerates absence. #[] exists for CTX-18 and for the suite, and
  # core calls it nowhere -- which is how CTX-13's "MUST NOT rely on any specific entry
  # surviving" is obeyed structurally rather than by care. CTX-19's reachability holds because the
  # map is a strong Hash; Dexpace/NoWeakReferences is what keeps it one, and neither the cop nor
  # the suite can reach a third-party reimplementation, which CTX-19 addresses and these gates
  # cannot.
  class ContextStore
    # The bound the process-wide store is built with when the chain supplies none. CTX-11 and
    # XCUT-14 name no number; AUTH-19 names 1024 as the default for a bounded store of exactly
    # this shape, and it is the only number the specification supplies for one (P4-9).
    MAX_TRACKED_CONTEXTS = 1024

    class << self
      # The one process-wide instance. Not a constant: a live store cannot be frozen at
      # assignment, which a mutable constant must be.
      #
      # Constructed on the FIRST call, under one ::Thread::Mutex, with the cap read from the
      # layered chain -- Configuration::Keys::MAX_TRACKED_CONTEXTS, falling back to
      # MAX_TRACKED_CONTEXTS -- which is the configuration source phase 4a postponed to phase 5a.
      # Phase 4a assigned this at file load, and its reason still binds: a bare `@default ||=
      # new` is an unsynchronised read-modify-write over shared state (XCUT-11) with allocations
      # inside `new`, so two threads reaching .default first could each publish a store, and
      # CTX-11's cap and CTX-19's reachability would then hold per store rather than per process.
      # The mutex is what makes a first-call construction as sound as the load-time one was, and
      # a first-call construction is what lets a Dexpace.configure at boot reach the cap at all:
      # read at load, only the environment tier could ever have set it. CTX-17 stays inert --
      # constructing the store is not registering a context, and a .build that takes this default
      # still writes nothing to it.
      #
      # Once published, the reference is read without the lock -- the shape Dexpace.configuration
      # has -- so a promotion after the first pays no lock. Before it, the chain is read OUTSIDE
      # the lock and only the `||=` runs inside it: the two seams are caller-supplied callables,
      # and the rule Dexpace.configure follows -- no user code under the mutex, which is
      # non-reentrant and would deadlock a seam that reached back into this store -- applies here
      # too. A racer that read the cap and lost the `||=` discards its read; the winner's cap is
      # the one read closest to the construction, which is "at first construction" as the design
      # states it.
      #
      # The consequence, stated because it is not obvious: the store is built once, so a
      # Dexpace.configure AFTER the first call does not resize it and neither does
      # Dexpace.reset_config!. A cap is a process-lifetime property here; a test that needs a
      # different one builds its own ContextStore.new(cap:), which is what the keyword is for.
      #
      # @return [ContextStore] the process-wide store
      def default
        @default || build_default
      end

      private

      # The first-call construction: the chain read before the lock, the publication under it.
      def build_default
        cap = configured_cap
        @default_mutex.synchronize { @default ||= new(cap: cap) }
      end

      # A configured value that is not a positive Integer -- unparseable, zero, negative -- falls
      # back to the constant rather than raising out of the first promotion, because
      # ContextStore.new(cap:) refuses such a cap and a misconfigured environment must not make
      # every request fail at its first context.
      def configured_cap
        cap = Dexpace.configuration.integer(Configuration::Keys::MAX_TRACKED_CONTEXTS,
                                            default: MAX_TRACKED_CONTEXTS,)
        cap.is_a?(::Integer) && cap.positive? ? cap : MAX_TRACKED_CONTEXTS
      end
    end

    @default_mutex = ::Thread::Mutex.new
    @default = nil

    # @param cap [Integer] the hard bound, a positive Integer; MAX_TRACKED_CONTEXTS unless a
    #   caller -- a test, or phase 5's configuration -- says otherwise
    def initialize(cap: MAX_TRACKED_CONTEXTS)
      @map = BoundedMap.new(cap: cap)
    end

    # CTX-8's unconditional overwrite: install-or-replace, never raising. Used by both promotions
    # and by nothing else in core.
    #
    # @param context [Context] the occupant, registered under its own #call_key
    # @return [Context] `context`
    def set(context)
      @map.set(context.call_key, context)
      context
    end

    # CTX-8's reject-on-duplicate insert: install only if absent, failing the loser with an error
    # whose message identifies the key. The conflict is detected under the map's mutex and the
    # error is raised after it is released. A separate strict-register affordance, as CTX-8 says;
    # no promotion uses it.
    #
    # @param context [Context] the occupant, registered under its own #call_key
    # @return [Context] `context`, when this call installed it
    # @raise [ContextConflictError] when the slot was already occupied
    def put(context)
      return context if @map.put(context.call_key, context)

      raise ContextConflictError, context.call_key
    end

    # CTX-18's explicit absent result. nil is legitimate here, and is the documented case
    # api-design/6ea28c9c reserves: the requirement demands an absent result and forbids raising.
    #
    # @param call_key [String] the slot
    # @return [Context, nil] the current occupant, or nil for an unknown or evicted key
    def [](call_key)
      @map[call_key]
    end

    # CTX-9's identity-conditional eviction, CTX-10's intermediate no-op and CTX-18's unknown-key
    # no-op: the slot is cleared only when its current occupant IS `context` (`equal?`), never by
    # value equality. Returns whether a slot was cleared, which is how CTX-10 is observable.
    #
    # @param context [Context] the closing context
    # @return [Boolean] whether it was the occupant and the slot was cleared
    def release(context)
      @map.delete_if_identical(context.call_key, context)
    end

    # The only aggregate read; there is no iteration, deliberately (CTX-13).
    #
    # @return [Integer] the number of registered contexts
    def size
      @map.size
    end
  end
end
