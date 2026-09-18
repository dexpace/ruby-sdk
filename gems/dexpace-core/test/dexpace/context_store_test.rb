# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_context"
require "open3"
require "rbconfig"

# CTX-7, CTX-8, CTX-9, CTX-10, CTX-11, CTX-12, CTX-13, CTX-18, CTX-19, XCUT-14, and the Fiber[]
# boundary docs/knowledge/notes/observability.md draws. Every store here is a fresh
# Dexpace::ContextStore.new(cap:), never .default: this suite passes alone and in any order and
# never touches the process-wide store. Every thread a case starts is joined before it returns,
# which DexpaceTestCase's teardown asserts.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the two
# operations and the eviction rules here, then Concurrency, Bound and Reachability below.
class DexpaceContextStoreTest < DexpaceTestCase
  # THE trap. Two contexts equal by value and distinct by identity are constructible only with a
  # pinned explicit call_key (CTX-5's escape hatch) -- FakeContext has no value equality at all
  # (plain Object#==), so this is the one case in the suite that needs a real Data context. A test
  # over two default-constructed contexts would pass against a ==-based release, because their
  # keys differ and the value comparison would never fire.
  test "CTX-9: release evicts only the reference-identical occupant, never a value-equal sibling" do
    store = Dexpace::ContextStore.new(cap: 8)
    bundle = Dexpace::Instrumentation::Bundle::NONE
    first = Dexpace::DispatchContext.build(bundle: bundle, call_key: "shared", store: store)
    second = Dexpace::DispatchContext.build(bundle: bundle, call_key: "shared", store: store)

    assert_equal(first, second)
    refute_same(first, second)

    store.set(first)

    refute(store.release(second))
    assert_same(first, store[first.call_key])

    assert(store.release(first))
    assert_nil(store[first.call_key])
  end

  test "CTX-8: #set is install-or-replace and never raises; #put is install-only-if-absent" do
    store = Dexpace::ContextStore.new(cap: 8)
    first = FakeContext.new(call_key: "k", store: store)
    second = FakeContext.new(call_key: "k", store: store)

    assert_same(first, store.put(first))
    assert_same(second, store.set(second))
    assert_same(second, store["k"])

    error = assert_raises(Dexpace::ContextConflictError) { store.put(first) }

    assert_equal("k", error.call_key)
    assert_same(second, store["k"], "a losing #put leaves the occupant untouched")
  end

  test "CTX-10: releasing a promoted intermediate is a no-op; the successor keeps the slot" do
    store = Dexpace::ContextStore.new(cap: 8)
    intermediate = FakeContext.new(call_key: "k", store: store)
    successor = FakeContext.new(call_key: "k", store: store)
    store.set(intermediate)
    store.set(successor)

    refute(store.release(intermediate))
    assert_same(successor, store["k"])
    assert_equal(1, store.size)
  end

  test "CTX-18: an unknown key resolves to nil and never raises" do
    store = Dexpace::ContextStore.new(cap: 8)

    assert_nil(store["nope"])
  end

  test "CTX-18: double-close and cleanup-path close are well-defined no-ops" do
    store = Dexpace::ContextStore.new(cap: 8)
    ctx = FakeContext.new(call_key: "x", store: store)

    refute(store.release(ctx))

    store.set(ctx)

    assert(store.release(ctx))
    refute(store.release(ctx))
    assert_equal(0, store.size)
  end

  # Verified fact 12: a frozen String is stored as a Hash key by identity, an unfrozen one is
  # duplicated and frozen. The store reads whatever #call_key answers, so a fake's unfrozen key
  # still resolves -- the freezing is the contexts' own job (CTX-4) and not the store's.
  test "the store resolves an unfrozen key the same as a frozen one" do
    store = Dexpace::ContextStore.new(cap: 8)
    ctx = FakeContext.new(call_key: +"mutable", store: store)
    store.set(ctx)

    assert_same(ctx, store["mutable"])
    assert_same(ctx, store[+"mutable"])
  end

  # CTX-7 and CTX-8 under contention, and the Fiber[] boundary.
  class ConcurrencyTest < DexpaceTestCase
    test "CTX-7: 16 threads registering 1000 distinct keys each lose nothing" do
      store = Dexpace::ContextStore.new(cap: 20_000)

      threads = Array.new(16) do |t|
        ::Thread.new do
          1000.times { |i| store.set(FakeContext.new(call_key: "t#{t}-#{i}", store: store)) }
        end
      end
      threads.each(&:join)

      assert_equal(16_000, store.size)
    end

    # testing/80c44c7f: the raised object is asserted on, not rescued and ignored.
    test "CTX-8: 32 threads racing one #put admit exactly one winner; every loser names the key" do
      store = Dexpace::ContextStore.new(cap: 64)
      gate = ::Thread::Queue.new
      outcomes = ::Thread::Queue.new

      threads = Array.new(32) do
        ::Thread.new do
          gate.pop
          outcomes << begin
            store.put(FakeContext.new(call_key: "shared", store: store))
            :ok
          rescue Dexpace::ContextConflictError => error
            error
          end
        end
      end
      32.times { gate << true }
      threads.each(&:join)
      results = Array.new(32) { outcomes.pop }

      winners = results.count { |r| r == :ok }
      losers = results.grep(Dexpace::ContextConflictError)

      assert_equal(1, winners)
      assert_equal(31, losers.size)
      losers.each do |error|
        assert_equal("shared", error.call_key)
        assert_includes(error.message, "shared")
      end
      assert_equal(1, store.size)
    end

    # The store is process-wide, not fiber-scoped: the line docs/knowledge/notes/observability.md
    # draws between CTX's store and the Fiber[] diagnostic-context carrier. The setup guard is
    # what makes the three store assertions mean something, and it covers every carrier they do:
    # with a fiber-storage slot and a fiber-local slot both written on the main fiber, a child
    # Fiber, a new ::Thread and an Enumerator's internal fiber each inherit the first and see
    # none of the second (observability/016d9154, verified on 3.2.11, 3.4.10 and 4.0.6). That is
    # what establishes the three as distinct execution contexts -- without it, the store being
    # visible everywhere would prove nothing. Fiber[:probe] = v emits no warning on any supported
    # Ruby (design, verified fact 13); only Fiber#storage= does, and nothing here calls it.
    test "the store is process-wide, not fiber-scoped -- the Fiber[] boundary" do
      store = Dexpace::ContextStore.new(cap: 8)
      ctx = FakeContext.new(call_key: "fiber-probe", store: store)
      store.set(ctx)
      probe = -> { [Fiber[:probe], ::Thread.current[:probe]] }

      Fiber[:probe] = :fiber_storage
      ::Thread.current[:probe] = :fiber_local

      assert_equal(%i[fiber_storage fiber_local], probe.call)
      assert_equal([:fiber_storage, nil], Fiber.new { probe.call }.resume)
      assert_equal([:fiber_storage, nil], ::Thread.new { probe.call }.value)
      assert_equal([:fiber_storage, nil], Enumerator.new { |y| y << probe.call }.next)

      from_fiber = Fiber.new { store["fiber-probe"] }.resume
      from_thread = ::Thread.new { store["fiber-probe"] }.value
      from_enumerator = Enumerator.new { |y| y << store["fiber-probe"] }.next

      assert_same(ctx, from_fiber)
      assert_same(ctx, from_thread)
      assert_same(ctx, from_enumerator)
    ensure
      Fiber[:probe] = nil
      ::Thread.current[:probe] = nil
    end
  end

  # CTX-11, CTX-12, CTX-13 and XCUT-14: the bound, the drain and the victim policy.
  class BoundTest < DexpaceTestCase
    test "CTX-13: cap pressure evicts the first-registered; re-setting a key does not refresh it" do
      store = Dexpace::ContextStore.new(cap: 3)
      a = FakeContext.new(call_key: "a", store: store)
      b = FakeContext.new(call_key: "b", store: store)
      c = FakeContext.new(call_key: "c", store: store)
      store.set(a)
      store.set(b)
      store.set(c)

      # Simulates a promotion overwriting "a"'s slot: Hash#[]= on an existing key does not move
      # it (verified fact 8), so "a" is still the oldest registration and the first victim.
      store.set(FakeContext.new(call_key: "a", store: store))
      store.set(FakeContext.new(call_key: "d", store: store))

      assert_equal(3, store.size)
      assert_nil(store["a"])
      assert_same(b, store["b"])
      assert_same(c, store["c"])
      refute_nil(store["d"])
    end

    # The same policy through a REAL promotion, which the fake above only simulates. A
    # #promote_to_exchange that released its source before setting the successor would pass
    # every FakeContext case in this file and still refresh the chain's eviction position (the
    # slot is deleted and re-inserted at the end of the hash) -- and leave the slot transiently
    # empty between two mutex acquisitions. Cap 3, three chains at the request stage under keys
    # a, b and c; a's request context promoted to exchange, re-setting a's slot through the real
    # path; a fourth chain promoted; a is still the oldest registration and still the victim, and
    # both of a's links close as CTX-18's false. This is the case the release-then-set mutation
    # goes red on.
    test "CTX-13: a real promotion re-sets the slot without refreshing its eviction position" do
      store = Dexpace::ContextStore.new(cap: 3)
      bundle = Dexpace::Instrumentation::Bundle::NONE
      promote = lambda do |key|
        Dexpace::DispatchContext.build(bundle: bundle, call_key: key, store: store)
          .promote_to_request(request: :req)
      end
      a = promote.call("a")
      b = promote.call("b")
      c = promote.call("c")

      a_exchange = a.promote_to_exchange(response: :resp)

      assert_same(a_exchange, store["a"])
      assert_equal(3, store.size)

      d = promote.call("d")

      assert_equal(%w[b c d], %w[a b c d].select { |key| store[key] })
      assert_equal(3, store.size)
      assert_same(b, store["b"])
      assert_same(c, store["c"])
      assert_same(d, store["d"])
      refute(a_exchange.close)
      refute(a.close)
    end

    test "CTX-13/CTX-18: nothing in the store's own behaviour depends on any entry surviving" do
      store = Dexpace::ContextStore.new(cap: 1)
      a = FakeContext.new(call_key: "a", store: store)
      store.set(a)
      store.set(FakeContext.new(call_key: "b", store: store))

      refute(store.release(a))
      assert_equal(1, store.size)
    end

    test "CTX-11/CTX-12/XCUT-14: the cap bound holds under concurrent inserts, from 16 threads" do
      store = Dexpace::ContextStore.new(cap: 64)

      threads = Array.new(16) do |t|
        ::Thread.new do
          500.times { |i| store.set(FakeContext.new(call_key: "#{t}-#{i}", store: store)) }
        end
      end
      threads.each(&:join)

      assert_equal(64, store.size)
    end

    # CTX-12/XCUT-14, and the assertion that is NOT the obvious one. The aggregate
    # drain-iteration count (inserts - final size) is an arithmetic identity that any
    # one-eviction-per-iteration drain reproduces, split-lock or no loop at all --
    # docs/knowledge/notes/execution-context.md records the measurement and the trap. What
    # discriminates single-threaded is this: from a store already at cap, every further insert
    # evicts EXACTLY ONE prior occupant and the size is never observed above the cap, which is
    # the drain body running at most once per insert. It fails against a drain that evicts two
    # per insert and against a #set path with no drain at all.
    #
    # What this canNOT reach, stated so nobody reads more into it: `while` vs a single `if` is
    # behaviourally identical under the one-synchronize insert-and-drain (the loop is written
    # because XCUT-14 makes it a MUST), and the split-lock overshoot the note measures is
    # invisible through this class's public surface -- #size takes the same mutex. Proving
    # CTX-7/CTX-8's drain needs a GVL-free interpreter: docs/first-release.md, Post-release
    # triggers, the IO-38 row.
    test "CTX-12/XCUT-14: from cap, each insert evicts exactly one, and size never exceeds cap" do
      store = Dexpace::ContextStore.new(cap: 8)
      seeds = Array.new(8) { |i| "seed-#{i}" }
      seeds.each { |key| store.set(FakeContext.new(call_key: key, store: store)) }

      sizes = []
      evictions = []
      keys = seeds.dup
      100.times do |i|
        before = keys.count { |key| store[key] }
        store.set(FakeContext.new(call_key: "fill-#{i}", store: store))
        sizes << store.size
        evictions << (before - keys.count { |key| store[key] })
        keys << "fill-#{i}"
      end

      assert_equal([8], sizes.uniq)
      assert_equal([1], evictions.uniq)
    end

    # XCUT-14 says "after each insert", and #put is an insert. Without this case the drain can
    # be deleted from the reject-on-duplicate path with the whole suite still green.
    test "CTX-8/CTX-11/XCUT-14: the reject-on-duplicate insert drains to the cap too" do
      store = Dexpace::ContextStore.new(cap: 3)

      6.times { |i| store.put(FakeContext.new(call_key: "p#{i}", store: store)) }

      assert_equal(3, store.size)
      assert_nil(store["p0"])
      refute_nil(store["p5"])
    end

    # P4-9's number, asserted rather than assumed: AUTH-19's stated default for a store of this
    # shape is the one number the specification supplies, and phase 5a (Task 13) attaches a
    # configuration source to it without changing a signature.
    test "CTX-11: MAX_TRACKED_CONTEXTS is 1024 and is the cap a default-constructed store uses" do
      assert_equal(1024, Dexpace::ContextStore::MAX_TRACKED_CONTEXTS)
      assert_predicate(Dexpace::ContextStore::MAX_TRACKED_CONTEXTS, :frozen?)

      store = Dexpace::ContextStore.new

      2000.times { |i| store.set(FakeContext.new(call_key: "d#{i}", store: store)) }

      assert_equal(Dexpace::ContextStore::MAX_TRACKED_CONTEXTS, store.size)
    end

    # A cap of 0 would evict every entry including the one just inserted, and a negative cap
    # would make `shift while size > cap` spin forever on an empty hash: both are refused at
    # construction, with SEAM-29's message for the absent case.
    test "cap: must be a positive Integer, with SEAM-29's one message form when absent" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::ContextStore.new(cap: nil) }

      assert_equal("cap is required", error.message)
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::ContextStore.new(cap: 0) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::ContextStore.new(cap: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::ContextStore.new(cap: 1.5) }
    end
  end

  # CTX-19 and the process-wide instance.
  class ReachabilityTest < DexpaceTestCase
    # A discriminator against ObjectSpace::WeakMap and NOT a tautology: the same run against a
    # WeakMap returns 0 of 1000 after three GC.starts on all three interpreters (design, verified
    # fact 3). It is equally NOT a discriminator against ObjectSpace::WeakKeyMap, which passes it
    # -- a WeakKeyMap holds its values strongly and the stored context strongly holds the frozen
    # String that is its key, so no entry is ever collectable (verified fact 3a). That spelling
    # is forbidden by Dexpace/NoWeakReferences and by nothing here. It names no ObjectSpace
    # constant, so it runs identically on 3.2.11, where WeakKeyMap is undefined.
    test "CTX-19: 1000 registered contexts stay reachable after the caller drops every local" do
      store = Dexpace::ContextStore.new(cap: 2048)
      keys = Array.new(1000) { |i| "k#{i}" }
      keys.each { |key| store.set(FakeContext.new(call_key: key, store: store)) }

      3.times { GC.start }

      assert_equal(1000, store.size)
      refute_nil(store[keys.first])
      refute_nil(store[keys.last])
    end

    # .default is the one process-wide instance; this suite never writes to it (CTX-17 keeps
    # construction off the store), so what is asserted here is its identity across calls and
    # that it is a store. The construction half is the next case's.
    test ".default is one process-wide instance, the same object on every call" do
      assert_same(Dexpace::ContextStore.default, Dexpace::ContextStore.default)
      assert_instance_of(Dexpace::ContextStore, Dexpace::ContextStore.default)
    end

    # Phase 4a assigned .default at file load, because `@default ||= new` is an unsynchronised
    # read-modify-write over shared state (XCUT-11). Phase 5a attached the cap's configuration
    # source and moved the construction to the FIRST call, under a mutex, so that a
    # Dexpace.configure at boot reaches the cap -- read at load, only the environment tier ever
    # could. The identity case cannot see either shape: by the time it runs some earlier .build
    # in this process has called .default. Only a fresh process can, so this asks one --
    # `require "dexpace"` and nothing else -- and checks that no store exists before the first
    # call and that the first two calls agree. The synchronisation half is
    # context_store_config_test.rb's race under a slow seam; the load-time shape prints
    # "false true" here, and an unsynchronised `||=` prints more than one store there.
    test ".default is built on its first call: a fresh process holds none before it" do
      lib = File.expand_path("../../lib", __dir__)
      out, err, status = Open3.capture3(
        { "RUBYOPT" => nil },
        RbConfig.ruby, "-w", "-W:deprecated", "-I", lib, "-e",
        'require "dexpace"; print Dexpace::ContextStore.instance_variable_get(:@default).nil?, ' \
        '" ", Dexpace::ContextStore.default.equal?(Dexpace::ContextStore.default)',
      )

      assert_predicate(status, :success?, err)
      assert_empty(err)
      assert_equal("true true", out)
    end
  end
end
