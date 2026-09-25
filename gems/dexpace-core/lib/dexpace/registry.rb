# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/seam_error"
require_relative "error/invalid_argument_error"
require_relative "closeable"
require_relative "version"

module Dexpace
  # Provider discovery, installation and conflict resolution, implemented once and instantiated
  # once per surviving seam.
  #
  # Ruby has no classpath to scan, so design §3.6 keeps all five of SEAM-5's precedence branches
  # and changes only the substrate: an adapter registers itself as a side effect of being
  # `require`d, and "discoverable" means "the application has required this adapter". Core ships an
  # empty registry and never auto-requires an optional gem, which is what keeps SEAM-1 true, and
  # the zero-candidate error names no gem, which is what keeps SEAM-2 true in the error path.
  #
  # The registry maps a key to a *factory* -- the adapter class, or any #call-shaped builder --
  # because require-time registration happens before the application has configured anything.
  # Resolution produces an *instance* and the resolved slot holds exactly one. SEAM-6's and
  # SEAM-8's prior-state table therefore compares `equal?` on the object in that slot: never ==,
  # and never the factory, because two calls of one factory produce two non-equal? instances the
  # requirement means to treat as different providers.
  #
  # State is one frozen Data snapshot in one instance variable, replaced wholesale under a
  # Thread::Mutex. A reader takes a single unsynchronised reference read and sees a consistent,
  # fully-constructed picture or the previous one, never a torn mixture -- which is SEAM-9's three
  # clauses implemented rather than argued, and IO-39's lock-free-read property surviving the seam
  # that used to state it. Concurrent::Map would be the styleguide's answer and is a gem
  # (docs/knowledge/notes/concurrency-and-async.md).
  #
  # One class, over the length cap: the five resolution branches, the install table, the swap
  # seam and the version-skew guard all read and write one snapshot, and splitting them for a
  # line count would scatter one invariant over several files (design §3.6).
  class Registry # rubocop:disable Metrics/ClassLength -- one snapshot, one class; see above
    # Design §2.3 mandates the two-segment pessimistic form and nothing else. Anything else is
    # refused rather than partially reimplemented.
    CORE_REQUIREMENT = Regexp.new("\\A~>\\s*(\\d+)\\.(\\d+)\\z", timeout: 1.0)
    private_constant :CORE_REQUIREMENT

    # The snapshot: a private_constant, so it does not include Dexpace::Model and has no .build
    # (design P2-9).
    State = ::Data.define(:factories, :resolved, :handed_out, :explicit, :resolving)
    private_constant :State

    # The resolution claim: the gate every other caller waits on, and the fiber that took it.
    #
    # The owner is what turns a re-entrant #resolve from a silent registry-wide wedge into a loud
    # error at the offending call. It is a Fiber and not a Thread for the same reason
    # Thread::Mutex's own ownership is per-fiber: two fibers of one thread can genuinely wait on
    # each other, and a factory that spawns a thread and resolves from it is not re-entrant at all.
    Claim = ::Data.define(:gate, :owner)
    private_constant :Claim

    # The Data instance is frozen by construction; its factories map is frozen here so the very
    # first snapshot obeys the same rule every later one does (a merge always yields a new map).
    EMPTY = State.new(
      factories: {}, resolved: nil, handed_out: false, explicit: false, resolving: nil,
    )
    EMPTY.factories.freeze
    private_constant :EMPTY

    # Whether `object` can be called with `arity` positional arguments. Both transport seams are
    # duck types over #call and this is the runtime half of that contract; the RBS interface in
    # sig/ is the static half.
    #
    # Computed from #parameters rather than from #arity: a non-lambda Proc reports its parameters
    # as :opt where a lambda reports :req (verified on 3.2.11, 3.4.10 and 4.0.6), so an #arity
    # equality would reject `proc { |a, b, c| }`, which SEAM-11's "a bare send lambda works as a
    # transport" is meant to admit. A required keyword refuses: the positional count can be right
    # and the call still fail, and a callable admitted here that raises ArgumentError at the first
    # send is the failure-at-use this predicate exists to move to registration. An object whose
    # #call comes from method_missing has no introspectable parameters, and is admitted rather
    # than refused.
    def self.callable?(object, arity:)
      return false unless object.respond_to?(:call)

      callable = object.is_a?(::Proc) || object.is_a?(::Method) ? object : object.method(:call)
      accepts_positionals?(callable.parameters, arity)
    rescue ::NameError
      true
    end

    # Whether a parameter list admits a call with exactly `arity` positional arguments and nothing
    # else: no required keyword, and the positional slots fit.
    def self.accepts_positionals?(parameters, arity)
      kinds = parameters.map(&:first)
      return false if kinds.include?(:keyreq)

      required = kinds.count(:req)
      optional = kinds.count(:opt)
      required <= arity && (kinds.include?(:rest) || required + optional >= arity)
    end
    private_class_method :accepts_positionals?

    # The seam's name, as it appears in every error message.
    attr_reader :seam

    # @param seam [String] the seam's name, as it appears in every error message
    # @param installer [String] the fully qualified explicit-install entry point, for the hint
    # @param conforms [#call] the seam's own .conforms? predicate
    def initialize(seam:, installer:, conforms:)
      @seam = seam.to_s.freeze
      @installer = installer.to_s.freeze
      @conforms = conforms
      @write = ::Thread::Mutex.new
      @state = EMPTY
    end

    # The keys of every registered factory, as a fresh list.
    def registered_keys = @state.factories.keys

    # Re-registering the `equal?` factory under one key is a no-op, so a double require is quiet;
    # a different factory under an occupied key raises, so two gems claiming one key are not.
    # `core:` is design §2.3's version-skew guard and is required, because an optional skew check
    # is a skew check nobody passes.
    #
    # The conflict is raised outside the lock: the message calls #inspect on two user objects,
    # and a factory whose #inspect reaches back into this registry would otherwise meet
    # `ThreadError: recursive locking` instead of the argument error -- the rule this file states
    # for every synchronize block is a snapshot swap and nothing else.
    def register(key, factory, core:)
      assert_core_version!(key, core)
      incumbent = @write.synchronize do
        current = @state.factories[key]
        if current.equal?(factory)
          nil
        elsif current
          current
        else
          added = { key => factory } #: Hash[untyped, untyped]
          @state = @state.with(factories: @state.factories.merge(added).freeze)
          nil
        end
      end
      return self if incumbent.nil?

      raise Dexpace::InvalidArgumentError,
            "#{@seam} key #{key.inspect} is already registered to #{incumbent.inspect}; " \
            "#{factory.inspect} was rejected"
    end

    # SEAM-5's "an explicitly installed provider always wins", with SEAM-6's conflict rule and
    # SEAM-8's warning. Both the warning and the conflict are emitted outside the lock: the
    # warning writes to a stream, and the conflict's message calls #inspect on two providers
    # (#register's note).
    def install(provider)
      refuse(provider) unless @conforms.call(provider)
      incumbent, replaced_after_handout = swap_in(provider)
      conflict!(incumbent, provider) unless incumbent.nil?
      warn_replaced(provider) if replaced_after_handout
      self
    end

    # Single-flight, with **no factory call and no #conforms? call under the lock**. The naive
    # shape -- build inside @write.synchronize -- deadlocks with `ThreadError: deadlock; recursive
    # locking` the moment a factory resolves anything from the same registry, because Ruby's Mutex
    # is non-reentrant, and it violates this file's own rule that a mutex is held across a snapshot
    # swap and nothing else.
    #
    # So the claim is a snapshot swap like any other: the winner puts a Thread::Queue in the
    # `resolving` slot and builds outside the lock, and every other caller blocks on that queue
    # until the winner closes it. That keeps SEAM-9's "a concurrent first-access cannot run the
    # discovery scan twice" while the scan itself runs unlocked, and it is scheduler-transparent
    # for the same reason the pivot's wait is: a blocking Thread::Queue pop routes through a
    # registered Fiber.scheduler rather than parking the OS thread. A resolution that raises clears
    # the slot and every waiter retries, which is SEAM-7's "an UNRESOLVED state MUST remain
    # re-evaluable".
    #
    # **A factory that resolves the registry it is being built by raises**, and the check is the
    # owner recorded in the claim. Without it that caller parks on the gate it took itself and
    # never returns, and every other caller then parks on the same gate: measured, one
    # self-resolving thread plus four unrelated resolvers left five hung, and a two-registry cycle
    # hung too. The shape this replaced -- build under @write -- raised `ThreadError: deadlock;
    # recursive locking` immediately from the offending call, and this comment already named that
    # scenario as the motivation for replacing it, so trading a loud error for a silent wedge would
    # be a straight regression. The claim is released by #complete_resolution's ensure on this path
    # exactly as on any other, so the registry stays re-evaluable for everyone else.
    #
    # **Why the loop terminates** (phase 10, answering phase 9's finding that nothing stated it).
    # Every pass ends in one of four ways, and only the last repeats. (1) A resolved slot returns
    # at once. (2) A fresh claim runs #complete_resolution, which returns or raises -- it never
    # loops. (3) The claim swap answers nil only when a provider was resolved between the two
    # reads, so the next pass is (1). (4) A claim owned by another fiber is waited on, and its gate
    # is closed in that owner's `ensure` whether the build succeeded or raised, and a pop on a
    # closed queue returns at once; the owner's slot is cleared in the same `ensure`, so the next
    # pass meets (1) when the owner succeeded or takes a fresh claim, (2), when it failed. So a
    # caller repeats at most once per concurrent claim that FAILED ahead of it, each of which is a
    # real exception raised to that claim's owner. The argument rests on the guard in (1) being
    # unconditional: phase 9 made it conditional on anything else and the loop span forever with
    # no progress. `registry_test.rb`'s Termination suite pins every state under a bounded join.
    def resolve
      loop do
        resolved = @state.resolved
        return hand_out(resolved) if resolved

        claim, fresh = take_or_join_claim
        return complete_resolution(claim.gate) if fresh && claim

        wait_on(claim)
      end
    end

    # SEAM-6's "separate unchecked/internal swap seam ... for test-scoped overrides", taken
    # explicitly and in the safest shape Ruby offers: block-scoped, restoring the prior snapshot in
    # an ensure, performing no conflict check. It records the override as auto-resolved rather than
    # explicitly installed, because a swap is not an install.
    def swap(provider)
      raise Dexpace::InvalidArgumentError, "swap requires a block" unless block_given?

      previous = @write.synchronize do
        was = @state
        @state = was.with(resolved: provider, handed_out: false, explicit: false)
        was
      end
      begin
        yield provider
      ensure
        # Two members are spliced from the LIVE state rather than restored from the captured
        # snapshot, and both for the same reason: the live value is the only correct one.
        #
        # `resolving`, because a resolution can be in flight when the swap begins and can complete
        # inside the block, and putting that snapshot's now-closed gate back would leave every
        # later #resolve popping a closed queue forever.
        #
        # `factories`, because a registration is a monotonic require-time fact and Ruby will not
        # re-run a `require`. An adapter registers itself as a side effect of being required
        # (design §3.6), so `require "some-adapter"` inside a swap block is a registration nothing
        # can redo: reverting it loses that adapter for the rest of the process, silently.
        # Verified: `swap(:fake) { register(:key, ...) }` left #registered_keys empty.
        #
        # `resolved`, `explicit` and `handed_out` ARE restored, because scoping an override to a
        # block is what #swap is for, and an #install inside the block is part of that override.
        @write.synchronize do
          live = @state
          @state = previous.with(resolving: live.resolving, factories: live.factories)
        end
      end
    end

    private

    # The install swap, and nothing else, under the lock: the conflicting incumbent when there
    # is one (and then no swap), and whether the provider replaced one that had already been
    # handed out. Both are reported out so the conflict and the warning happen after the block.
    def swap_in(provider)
      @write.synchronize do
        state = @state
        next [nil, false] if state.resolved.equal?(provider)
        next [state.resolved, false] if state.resolved && state.explicit

        @state = state.with(resolved: provider, handed_out: false, explicit: true)
        [nil, !state.resolved.nil? && state.handed_out]
      end
    end

    # The claim swap: a fresh claim for this fiber when the slot is free, the in-flight claim to
    # wait on when it is not, and nothing at all once a provider is resolved. The second element
    # says which of the first two happened, because a fresh claim and a re-entrant one both name
    # the calling fiber as owner.
    def take_or_join_claim
      @write.synchronize do
        state = @state
        if state.resolved
          [nil, false]
        elsif state.resolving
          [state.resolving, false]
        else
          claim = Claim.new(gate: ::Thread::Queue.new, owner: ::Fiber.current)
          @state = state.with(resolving: claim)
          [claim, true]
        end
      end
    end

    # Parks on an in-flight claim until its owner closes the gate -- unless the owner is this very
    # fiber, which is the re-entrant call and is refused rather than parked. A nil claim means
    # the slot was resolved between two reads, and the loop's next read hands it out.
    def wait_on(claim)
      return if claim.nil?

      raise_reentrant! if claim.owner.equal?(::Fiber.current)
      claim.gate.pop unless @state.resolved
    end

    def conflict!(incumbent, provider)
      raise Dexpace::InvalidArgumentError,
            "a #{@seam} provider is already installed (#{incumbent.inspect}); " \
            "#{provider.inspect} was rejected"
    end

    def raise_reentrant!
      raise Dexpace::SeamError,
            "re-entrant #{@seam} resolution: a #{@seam} factory called #resolve on the registry " \
            "that is building it, directly or through a cycle of registries. The provider it " \
            "would return does not exist yet."
    end

    # Runs outside @write.
    #
    # The claim is released in `ensure` and not in a `rescue StandardError`. A factory can raise
    # something that is not a StandardError -- a LoadError from an adapter factory that requires
    # its own dependency lazily is the realistic case, and NotImplementedError, Interrupt and
    # NoMemoryError are the rest -- and a claim released only on the StandardError path leaves a
    # closed gate latched in the slot, after which every later #resolve pops a closed queue,
    # finds nothing resolved and loops: a silent spin at 100% CPU with no exception, which is
    # strictly worse than the deadlock this shape replaced. It also breaks SEAM-7's "an UNRESOLVED
    # state MUST remain re-evaluable", which is the contract this method exists to keep.
    #
    # An explicit #install that won the race while this was building keeps its provider and the
    # freshly built one is discarded -- and is closed, because a transport provider is the
    # archetypal owner of a pool (SEAM-14) and this phase already closes exactly this shape in
    # Completer#fulfil (SEAM-30). close_quietly is a no-op on a provider with no #close.
    def complete_resolution(gate)
      provider = build_sole_provider
      settled = @write.synchronize do
        @state = @state.with(resolved: provider, explicit: false) unless @state.resolved
        @state.resolved
      end
      Dexpace.close_quietly(provider) unless settled.equal?(provider)
      hand_out(settled)
    ensure
      @write.synchronize { @state = @state.with(resolving: nil) }
      gate.close
    end

    def hand_out(provider)
      @write.synchronize { @state = @state.with(handed_out: true) } unless @state.handed_out
      provider
    end

    def build_sole_provider
      key = sole_key
      factory = @state.factories.fetch(key)
      provider = factory.respond_to?(:call) ? factory.call : factory.new
      unless @conforms.call(provider)
        raise Dexpace::SeamError,
              "the #{@seam} factory registered under #{key.inspect} produced a " \
              "#{provider.class}, which does not implement the seam"
      end

      provider
    end

    # SEAM-5's two loud branches: zero candidates, naming the action and no gem (SEAM-2), and
    # more than one, listing every key.
    def sole_key
      keys = @state.factories.keys
      if keys.empty?
        raise Dexpace::SeamError,
              "no #{@seam} provider is registered. Require an adapter gem that registers one, " \
              "or install one explicitly with #{@installer}."
      end
      if keys.size > 1
        raise Dexpace::SeamError,
              "more than one #{@seam} provider is registered " \
              "(#{keys.map(&:inspect).join(", ")}). Install the one you want explicitly with " \
              "#{@installer}."
      end

      keys.fetch(0)
    end

    def refuse(provider)
      raise Dexpace::InvalidArgumentError,
            "a #{@seam} provider must implement the seam; #{provider.class} does not"
    end

    # SEAM-8 is a SHOULD asking for a warning rather than a failure. Kernel#warn routes through
    # Warning.warn, so a host can intercept, redirect or silence it; verified suppressed when
    # $VERBOSE is nil, which is the right property for an advisory -- and it means a consumer
    # running -W0 will not see it, which is stated here rather than discovered (design P2-6).
    def warn_replaced(provider)
      warn("dexpace: a #{@seam} provider that had already been handed out was replaced by " \
           "#{provider.inspect}; objects built against the previous one may still be in use")
    end

    # Postponed by phase 0 and built here: the runtime half of design §2.3's version-skew guard.
    #
    # Hand-rolled rather than built on Gem::Requirement, because `Gem` is undefined under
    # `ruby --disable-gems` (verified on 3.2.11 and 4.0.6) and a library may not assume RubyGems is
    # loaded; `rubygems` is also not on phase 0's require allowlist. Only the two-segment `~> M.N`
    # form design §2.3 mandates is accepted -- anything else is refused rather than partially
    # reinterpreted -- and Task 8's test cross-checks this comparison against
    # Gem::Requirement#satisfied_by? over a grid, where RubyGems is present.
    def assert_core_version!(key, requirement)
      match = requirement.is_a?(::String) ? CORE_REQUIREMENT.match(requirement) : nil
      unless match
        raise Dexpace::InvalidArgumentError,
              "core: must be a two-segment pessimistic requirement such as \"~> 1.2\", " \
              "got #{requirement.inspect}"
      end

      wanted_major = match[1].to_i
      wanted_minor = match[2].to_i
      running = Dexpace::VERSION.split(".", 3)
      return if running.fetch(0).to_i == wanted_major && running.fetch(1).to_i >= wanted_minor

      raise Dexpace::SeamError,
            "#{@seam} adapter #{key.inspect} was built against dexpace-core #{requirement}, " \
            "but dexpace-core #{Dexpace::VERSION} is loaded"
    end
  end
end
