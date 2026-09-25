# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/warning_capture"
require "dexpace"

# SEAM-5, SEAM-6, SEAM-7, SEAM-8, SEAM-9, SEAM-2, XCUT-23. Ruby has no classpath, so design §3.6
# changes the substrate -- an adapter registers itself as a side effect of being required -- and
# keeps all five precedence branches. State is one frozen Data snapshot swapped under a
# Thread::Mutex, so a reader takes one unsynchronised reference read and sees a consistent picture.
#
# Six classes because Metrics/ClassLength caps one at 100 lines: the five resolution branches
# here, then Callable (the #call duck type's runtime half), Installation (SEAM-6/SEAM-8),
# Concurrency (SEAM-9), Reentrancy (a factory, or an #inspect, that reaches back into a
# registry) and Swap (the unchecked override seam).
class DexpaceRegistryTest < DexpaceTestCase
  CORE = "~> 0.0"

  # One shared factory for the registry-driving classes, so every registry under test is shaped
  # the same.
  module Builds
    def registry(conforms: ->(_object) { true })
      Dexpace::Registry.new(
        seam: "transport",
        installer: "Dexpace::Transport.install",
        conforms: conforms,
      )
    end
  end
  include Builds

  test "zero candidates raise a descriptive error naming no gem" do
    error = assert_raises(Dexpace::SeamError) { registry.resolve }

    assert_match(/no transport provider is registered/, error.message)
    assert_match(/Dexpace::Transport\.install/, error.message)
    refute_match(%r{net_http|async_http|net/http|json|oj|excon|typhoeus}i, error.message,
                 "SEAM-2: core names no concrete implementation, not even in the error path",)
  end

  test "exactly one candidate resolves silently and is memoised" do
    subject = registry
    built = 0
    subject.register(:fake, lambda {
      built += 1
      Object.new
    }, core: CORE,)

    first = subject.resolve

    assert_same(first, subject.resolve, "SEAM-7: a successful resolution is cached process-wide")
    assert_equal(1, built)
  end

  test "two candidates raise an error listing every registered key" do
    subject = registry
    subject.register(:alpha, -> { :alpha }, core: CORE)
    subject.register(:beta, -> { :beta }, core: CORE)

    error = assert_raises(Dexpace::SeamError) { subject.resolve }

    assert_match(/:alpha/, error.message)
    assert_match(/:beta/, error.message)
  end

  test "a failed resolution memoises nothing and a later registration takes effect" do
    subject = registry

    assert_raises(Dexpace::SeamError) { subject.resolve }

    subject.register(:late, -> { :late }, core: CORE)

    assert_equal(:late, subject.resolve, "SEAM-7: an unresolved state stays re-evaluable")
  end

  test "re-registering the identical factory under one key is a no-op" do
    subject = registry
    factory = -> { :provider }
    subject.register(:key, factory, core: CORE)

    assert_same(subject, subject.register(:key, factory, core: CORE))
    assert_equal([:key], subject.registered_keys)
  end

  test "a different factory under an occupied key raises naming both" do
    subject = registry
    subject.register(:key, -> { :first }, core: CORE)

    error = assert_raises(Dexpace::InvalidArgumentError) do
      subject.register(:key, -> { :second }, core: CORE)
    end

    assert_match(/already registered/, error.message)
    assert_equal([:key], subject.registered_keys, "no partial side effect")
    assert_equal(:first, subject.resolve)
  end

  test "a class factory is instantiated and a callable factory is called" do
    subject = registry
    klass = Class.new
    subject.register(:key, klass, core: CORE)

    assert_instance_of(klass, subject.resolve)
  end

  test "a factory whose product does not implement the seam fails loudly at resolve" do
    subject = registry(conforms: ->(object) { object.is_a?(Symbol) })
    subject.register(:key, -> { Object.new }, core: CORE)

    error = assert_raises(Dexpace::SeamError) { subject.resolve }

    assert_match(/does not implement the seam/, error.message)
  end

  test "seam and registered_keys read back; registered_keys is a fresh list" do
    subject = registry
    subject.register(:key, -> { :p }, core: CORE)

    assert_equal("transport", subject.seam)
    assert_equal([:key], subject.registered_keys)
    refute_same(subject.registered_keys, subject.registered_keys)
  end

  # The runtime half of the #call duck type both transport seams share (SEAM-11, SEAM-16): what
  # Transport.conforms? and AsyncTransport.conforms? are made of.
  class Callable < DexpaceTestCase
    test "callable? accepts every callable shape that can take three positional arguments" do
      assert(Dexpace::Registry.callable?(->(_a, _b, _c) {}, arity: 3))
      assert(Dexpace::Registry.callable?(proc { |_a, _b, _c| }, arity: 3))
      assert(Dexpace::Registry.callable?(->(*) {}, arity: 3))
      assert(Dexpace::Registry.callable?(->(_a, _b = 1, _c = 2) {}, arity: 3))
      refute(Dexpace::Registry.callable?(->(_a) {}, arity: 3))
      refute(Dexpace::Registry.callable?(->(_a, _b, _c, _d) {}, arity: 3))
      refute(Dexpace::Registry.callable?(Object.new, arity: 3))
      refute(Dexpace::Registry.callable?(nil, arity: 3))
    end

    # "Admits exactly `arity` positional arguments" has to mean the call succeeds with exactly
    # those and nothing else. A required keyword makes that call ArgumentError: missing keyword,
    # so a near-miss with three positionals and a `must:` would pass registration and fail at the
    # first send -- the outcome the predicate exists to prevent, and a stdlib error where the seam
    # promises InvalidArgumentError. An optional keyword, a keyword rest and a block parameter all
    # leave the positional call intact and stay admitted.
    test "callable? refuses a required keyword and admits the optional keyword shapes" do
      keyword_object = Class.new { def call(_request, _options, _cancellation, must:) = must }.new

      refute(Dexpace::Registry.callable?(->(_a, _b, _c, must:) {}, arity: 3))
      refute(Dexpace::Registry.callable?(->(*, must:) {}, arity: 3))
      refute(Dexpace::Registry.callable?(keyword_object, arity: 3))
      assert(Dexpace::Registry.callable?(->(_a, _b, _c, may: nil) {}, arity: 3))
      assert(Dexpace::Registry.callable?(->(_a, _b, _c, **) {}, arity: 3))
      assert(Dexpace::Registry.callable?(->(_a, _b, _c, &_block) {}, arity: 3))
    end

    # An object whose #call comes from method_missing has no introspectable parameters and is
    # admitted rather than refused, because refusing it would reject a legitimate delegator. So is
    # one that answers respond_to?(:call) without respond_to_missing?, whose #method raises
    # NameError: the predicate admits what it cannot read rather than refusing it.
    test "callable? admits a call reached through method_missing or an unreadable one" do
      ghost = Class.new do
        def respond_to_missing?(name, include_private = false) = name == :call || super
        def method_missing(name, *args) = name == :call ? args : super
      end.new
      liar = Class.new do
        def respond_to?(name, *) = name == :call || super
      end.new

      assert(Dexpace::Registry.callable?(ghost, arity: 3))
      assert(Dexpace::Registry.callable?(liar, arity: 3))
    end
  end

  # SEAM-6's conflict rule and SEAM-8's warning, by the prior-state table design §3.6 fixes.
  class Installation < DexpaceTestCase
    include Builds

    test "installing into an empty slot succeeds silently" do
      subject = registry
      provider = Object.new

      warnings = WarningCapture.record { subject.install(provider) }

      assert_empty(warnings)
      assert_same(provider, subject.resolve)
    end

    test "installing the identical instance twice is a no-op" do
      subject = registry
      provider = Object.new
      subject.install(provider)

      warnings = WarningCapture.record { subject.install(provider) }

      assert_empty(warnings)
      assert_same(provider, subject.resolve)
    end

    test "installing a different instance over an explicit install raises naming both" do
      subject = registry
      incumbent = Object.new
      subject.install(incumbent)

      error = assert_raises(Dexpace::InvalidArgumentError) { subject.install(Object.new) }

      assert_match(/already installed/, error.message)
      assert_same(incumbent, subject.resolve, "no partial side effect")
    end

    # SEAM-8's negative clause -- "no warning is warranted ... when the resolved provider was
    # never actually returned" -- holds **vacuously in production** here, because #resolve hands
    # out the provider in the same call that resolves it, so an auto-resolved-but-never-handed-out
    # slot is unreachable through the ordinary API. The unchecked swap seam SEAM-6 sanctions is the
    # only door into that state, which is what this exercises: the branch exists, is correct, and
    # would become live the day a non-delivering resolution path is added. It does not prove that
    # any production path reaches it, and must not be read as proving that.
    test "replacing a swapped-in provider that was never handed out is silent" do
      subject = registry

      subject.swap(:auto) do
        warnings = WarningCapture.record { subject.install(Object.new) }

        assert_empty(warnings)
      end
    end

    test "replacing an auto-resolved provider that was already handed out warns" do
      subject = registry
      subject.register(:key, -> { :auto }, core: CORE)
      subject.resolve

      warnings = WarningCapture.record { subject.install(Object.new) }

      assert_equal(1, warnings.size)
      assert_match(/already been handed out/, warnings.first)
    end

    test "an explicit install wins over a registered factory and is never scanned past" do
      subject = registry
      subject.register(:key, -> { flunk("SEAM-5: an installed provider always wins") }, core: CORE)
      provider = Object.new

      subject.install(provider)

      assert_same(provider, subject.resolve)
    end

    test "install refuses a provider that does not implement the seam" do
      subject = registry(conforms: ->(object) { object.is_a?(Symbol) })

      error = assert_raises(Dexpace::InvalidArgumentError) { subject.install(Object.new) }

      assert_match(/must implement the seam/, error.message)
    end
  end

  # SEAM-9's three clauses, and the re-entrancy cases a "build under the lock" shape gets wrong.
  class Concurrency < DexpaceTestCase
    include Builds

    test "a concurrent first access runs the discovery scan exactly once" do
      subject = registry
      built = 0
      counter = ::Thread::Mutex.new
      subject.register(:key, lambda {
        counter.synchronize { built += 1 }
        Object.new
      }, core: CORE,)
      results = ::Queue.new

      Array.new(32) { ::Thread.new { results << subject.resolve } }.each(&:join)

      resolved = []
      resolved << results.pop until results.empty?

      assert_equal(1, resolved.map(&:object_id).uniq.size, "SEAM-9: exactly-once resolution")
      assert_equal(1, built)
    end

    # The single-flight gate from the waiter's side: a second resolver arriving while the first is
    # still building parks on the claim's Thread::Queue and receives the very instance the winner
    # built, with the factory called once. The 32-thread test above cannot promise a waiter ever
    # parks -- under the GVL the winner may finish before anyone else reaches the claim -- so the
    # factory is held open here until the second resolver is known to be waiting.
    test "a second resolver parks on the in-flight claim and receives the winner's instance" do
      subject = registry
      started = ::Queue.new
      release = ::Queue.new
      built = 0
      subject.register(:key, lambda {
        built += 1
        started << :in_factory
        release.pop
        Object.new
      }, core: CORE,)

      winner = ::Thread.new { subject.resolve }
      started.pop
      waiter = ::Thread.new { subject.resolve }
      sleep(0.05)
      release << :go

      assert(winner.join(5) && waiter.join(5), "a waiter never woke from the gate")
      assert_same(winner.value, waiter.value)
      assert_equal(1, built, "SEAM-9: the scan ran once")
    end

    test "two concurrent installs cannot both pass the conflict check" do
      subject = registry
      accepted = ::Queue.new

      Array.new(16) do
        ::Thread.new do
          subject.install(Object.new)
          accepted << 1
        rescue Dexpace::InvalidArgumentError
          nil
        end
      end.each(&:join)

      assert_equal(1, accepted.size, "SEAM-9: writes are serialized")
    end

    # Each of these takes the registry's OWN write mutex from inside the factory or the conformance
    # predicate, which is what makes them bite: under a "build inside @write.synchronize" shape
    # every one raises ThreadError: deadlock; recursive locking on every supported Ruby. A test
    # whose factory only calls #registered_keys would pass under that shape too, because
    # #registered_keys takes no lock -- and a regression test that passes under the bug is worse
    # than no test.
    test "a factory that takes the registry's own write lock does not deadlock" do
      subject = registry
      installed = Object.new
      subject.register(:key, lambda {
        subject.install(installed) # #install takes @write
        Object.new
      }, core: CORE,)

      assert_same(installed, subject.resolve,
                  "an explicit install that lands mid-build wins; the built provider is dropped",)
    end

    test "the conformance predicate can take the write lock, so it is not called under it" do
      observed = []
      subject = nil
      subject = Dexpace::Registry.new(
        seam: "transport",
        installer: "Dexpace::Transport.install",
        conforms: lambda { |_provider|
          subject.swap(:probe) { observed << :ran } # #swap takes @write, twice
          true
        },
      )
      subject.register(:key, -> { Object.new }, core: CORE)

      subject.resolve

      assert_equal([:ran], observed)
    end

    test "a factory that resolves another registry does not deadlock" do
      inner = registry
      inner.register(:inner, -> { :inner_provider }, core: CORE)
      outer = registry
      outer.register(:outer, -> { inner.resolve }, core: CORE)

      assert_equal(:inner_provider, outer.resolve)
    end
  end

  # A factory that reaches back into a registry: the three re-entrancy cases, which the
  # "resolves ANOTHER registry" test in Concurrency does not reach, and the LoadError case.
  class Reentrancy < DexpaceTestCase
    include Builds

    # The three re-entrancy cases, which the "resolves ANOTHER registry" test above does not
    # reach. A factory that resolves its OWN registry parks on the gate it took itself, and every
    # later caller then parks on the same gate: measured, one self-resolving thread plus four
    # unrelated resolvers left five hung on every supported Ruby. The shape this replaced raised
    # `ThreadError: deadlock; recursive locking` from the offending call, so a silent wedge would
    # be a straight regression.
    test "a factory that resolves its own registry raises rather than parking on its own gate" do
      subject = registry
      subject.register(:key, -> { subject.resolve }, core: CORE)

      error = assert_raises(Dexpace::SeamError) { subject.resolve }

      assert_match(/re-entrant transport resolution/, error.message)
    end

    test "a cycle of two registries raises rather than hanging both" do
      first = registry
      second = registry
      first.register(:first, -> { second.resolve }, core: CORE)
      second.register(:second, -> { first.resolve }, core: CORE)

      assert_raises(Dexpace::SeamError) { first.resolve }
    end

    # The claim is released in #complete_resolution's ensure on this path like any other, so the
    # registry is re-evaluable for everyone else. The join timeout is the assertion: without it
    # the suite hangs instead of failing.
    test "a re-entrant resolve leaves the registry re-evaluable for every other caller" do
      subject = registry
      reentrant = true
      subject.register(:key, lambda {
        next subject.resolve if reentrant

        :provider
      }, core: CORE,)

      assert_raises(Dexpace::SeamError) { subject.resolve }
      reentrant = false

      later = ::Thread.new { subject.resolve }

      assert(later.join(5), "a re-entrant resolve wedged the whole registry")
      assert_equal(:provider, later.value)
    end

    # SEAM-7's "an UNRESOLVED state MUST remain re-evaluable", against the failure a rescue of
    # StandardError alone does not cover. A LoadError from an adapter factory that requires its own
    # dependency lazily is the realistic case; releasing the claim only on the StandardError path
    # leaves a closed gate latched and every later #resolve spinning at 100% CPU with no exception.
    # The join timeout is the assertion: without it the suite hangs instead of failing.
    test "a factory raising outside StandardError leaves the registry re-evaluable" do
      subject = registry
      first_attempt = true
      subject.register(:key, lambda {
        raise ::LoadError, "the adapter's own dependency is missing" if first_attempt

        :recovered
      }, core: CORE,)

      assert_raises(::LoadError) { subject.resolve }
      first_attempt = false

      retried = ::Thread.new { subject.resolve }

      assert(retried.join(5), "the registry wedged into a spin instead of re-evaluating")
      assert_equal(:recovered, retried.value)
    end

    # Both conflict messages interpolate #inspect of two user objects. Built under @write, an
    # #inspect that reaches back into the registry -- here one that registers a second key, which
    # takes the lock -- met `ThreadError: deadlock; recursive locking` instead of the argument
    # error, on every supported Ruby; the messages are built after the block, as the warning is.
    test "a registration conflict's message is built outside the lock" do
      subject = registry
      subject.register(:key, -> { :first }, core: CORE)

      error = assert_raises(Dexpace::InvalidArgumentError) do
        subject.register(:key, reaching_into(subject), core: CORE)
      end

      assert_match(/reaching/, error.message)
      assert_equal(%i[key probe], subject.registered_keys.sort)
    end

    test "an install conflict's message is built outside the lock" do
      subject = registry
      subject.install(Object.new)

      error = assert_raises(Dexpace::InvalidArgumentError) { subject.install(reaching_into(subject)) }

      assert_match(/reaching/, error.message)
      assert_equal([:probe], subject.registered_keys)
    end

    private

    # An object whose #inspect registers a key on `subject`, taking its write lock.
    def reaching_into(subject)
      reaching = Object.new
      reaching.define_singleton_method(:inspect) do
        subject.register(:probe, -> { :probe }, core: CORE)
        "reaching"
      end
      reaching
    end
  end

  # SEAM-6's "separate unchecked/internal swap seam ... for test-scoped overrides".
  class Swap < DexpaceTestCase
    include Builds

    test "swap is scoped to its block and restores the previous state" do
      subject = registry
      subject.register(:key, -> { :real }, core: CORE)

      assert_equal(:real, subject.resolve)

      subject.swap(:fake) do |provider|
        assert_equal(:fake, provider)
        assert_equal(:fake, subject.resolve)
      end

      assert_equal(:real, subject.resolve)
    end

    test "swap without a block is a caller mistake" do
      assert_raises(Dexpace::InvalidArgumentError) { registry.swap(:fake) }
    end

    test "swap restores the previous state when the block raises" do
      subject = registry
      subject.install(:installed)

      assert_raises(::IOError) { subject.swap(:fake) { raise ::IOError, "inside" } }

      assert_equal(:installed, subject.resolve)
    end

    # #swap is the seam every adapter suite will reach for, and a resolution can complete inside
    # its block. Restoring the pre-block snapshot wholesale would put that resolution's now-closed
    # gate back and wedge every later #resolve the same way.
    test "swap does not restore a stale resolution claim" do
      subject = registry
      started = ::Queue.new
      release = ::Queue.new
      blocking = true
      subject.register(:key, lambda {
        if blocking
          blocking = false
          started << :in_factory
          release.pop
        end
        :provider
      }, core: CORE,)

      resolver = ::Thread.new { subject.resolve }
      started.pop
      subject.swap(:fake) do
        release << :go
        resolver.join
      end

      later = ::Thread.new { subject.resolve }

      assert(later.join(5), "swap restored a closed gate and wedged the registry")
      assert_equal(:provider, later.value)
    end

    # An adapter registers itself as a side effect of being required, and Ruby will not re-run a
    # `require`, so a registration reverted by #swap's ensure is gone for the rest of the process.
    # `resolved`, `explicit` and `handed_out` ARE restored -- scoping an override is what swap is
    # for -- and `factories` is spliced from the live state for the same reason `resolving` is.
    test "swap does not revert a registration made inside its block" do
      subject = registry

      subject.swap(:fake) do
        subject.register(:key, -> { :real }, core: CORE)

        assert_equal(:fake, subject.resolve, "the override is still in force inside the block")
      end

      assert_equal([:key], subject.registered_keys,
                   "swap reverted a require-time registration, which no later require can redo",)
      assert_equal(:real, subject.resolve)
    end
  end

  # SEAM-5, XCUT-23 (phase 10, phase 9's hand-off): #resolve is a `loop do`, and phase 9 found
  # that conditioning its `return hand_out(resolved)` guard on anything else spins it forever
  # with no progress. The loop's termination is argued at #resolve; these pin the progress it
  # rests on -- every state a caller can meet returns in a bounded time -- with the call on its
  # own thread joined under a bound, so a regression fails here rather than hanging the run.
  class Termination < DexpaceTestCase
    include Builds

    def resolve_within(subject, seconds = 2.0)
      worker = ::Thread.new { subject.resolve }

      assert(worker.join(seconds), "#resolve made no progress within #{seconds}s")
      worker.value
    end

    test "an installed provider over a still-registered factory returns without a scan" do
      subject = registry
      subject.register(:key, -> { :scanned }, core: CORE)
      subject.install(:installed)

      assert_equal(:installed, resolve_within(subject))
    end

    test "a waiter whose claim owner raised retries, takes its own claim and returns" do
      subject = registry
      entered = ::Thread::Queue.new
      release = ::Thread::Queue.new
      attempts = 0
      subject.register(:key, lambda {
        attempts += 1
        next :built unless attempts == 1

        entered << true
        release.pop
        raise ::IOError, "the first build fails"
      }, core: CORE,)
      owner = ::Thread.new do
        subject.resolve
      rescue ::IOError => error
        error
      end
      entered.pop
      waiter = ::Thread.new { subject.resolve }
      Thread.pass until waiter.status == "sleep"
      release << true

      assert_kind_of(::IOError, owner.value)
      assert(waiter.join(2.0), "the waiter made no progress after the owner's claim failed")
      assert_equal(:built, waiter.value)
    end
  end
end
