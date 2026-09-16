# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-1 (the head of the chain), CTX-2, CTX-3, CTX-4, CTX-5, CTX-6, CTX-7, CTX-15, CTX-17.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the key
# and its equality here, then Promotion and Construction below.
class DexpaceDispatchContextTest < DexpaceTestCase
  # The untraced bundle every case in this file builds from (CTX-15).
  NONE = Dexpace::Instrumentation::Bundle::NONE

  test "CTX-5/CTX-6: two default-constructed contexts from the same bundle are NOT equal" do
    a = Dexpace::DispatchContext.build(bundle: NONE)
    b = Dexpace::DispatchContext.build(bundle: NONE)

    refute_equal(a, b)
    refute_operator(a, :eql?, b)
    refute_equal(a.hash, b.hash)
    assert_equal(2, { a => 1, b => 2 }.size)
  end

  test "CTX-5: an explicit shared call_key restores value equality" do
    a = Dexpace::DispatchContext.build(bundle: NONE, call_key: "shared")
    b = Dexpace::DispatchContext.build(bundle: NONE, call_key: "shared")

    assert_equal(a, b)
    assert_operator(a, :eql?, b)
    assert_equal(a.hash, b.hash)
    assert_equal(1, { a => 1, b => 2 }.size)
  end

  # This is the test that would fail if the key were ever derived from the bundle: the two
  # contexts share the very same Bundle::NONE object (asserted equal?, not merely ==), so every
  # bundle field is identical, and the keys still differ.
  test "CTX-15: minting from the SAME Bundle::NONE object still yields distinct keys" do
    bundle = NONE
    a = Dexpace::DispatchContext.build(bundle: bundle)
    b = Dexpace::DispatchContext.build(bundle: bundle)

    assert_same(bundle, a.bundle)
    assert_same(bundle, b.bundle)
    refute_equal(a.call_key, b.call_key)
  end

  # CTX-4's reference rendering, 'traceId:spanId:n': a rendered prefix plus a counter, so a key is
  # debuggable by eye, and the counter is what makes it call-unique when the prefix is not.
  test "CTX-4: a minted key is the bundle's trace id, its span id and a counter" do
    ctx = Dexpace::DispatchContext.build(bundle: NONE)
    prefix = "#{NONE.trace_id}:#{NONE.span_id}:"

    assert_operator(ctx.call_key, :start_with?, prefix)
    assert_match(/\A#{Regexp.escape(prefix)}[1-9][0-9]*\z/, ctx.call_key)
  end

  test "CTX-4: successive minted keys carry a strictly increasing counter" do
    counters = Array.new(5) do
      Dexpace::DispatchContext.build(bundle: NONE).call_key.split(":").last.to_i
    end

    assert_equal(counters, counters.sort)
    assert_equal(5, counters.uniq.size)
  end

  # One counter serves all three flavours: CTX-6 requires distinctness "across the whole
  # process and across all three context flavors", not across a store. Distinctness alone is
  # not the discriminating assertion -- a counter per flavour yields three distinct keys too,
  # whenever the shared counter has already moved past the per-flavour one -- so the suffix is
  # asserted to increase strictly ACROSS flavours in build order, which only one counter does.
  test "CTX-6: three flavours built from one untraced bundle draw from one counter" do
    bundle = NONE
    keys = Array.new(3).flat_map do
      [
        Dexpace::DispatchContext.build(bundle: bundle).call_key,
        Dexpace::RequestContext.build(bundle: bundle, request: :req).call_key,
        Dexpace::ExchangeContext.build(bundle: bundle, request: :req, response: :resp).call_key,
      ]
    end
    counters = keys.map { |key| key.split(":").last.to_i }

    assert_equal(9, keys.uniq.size)
    assert_equal(counters.sort, counters)
    assert_equal(counters.first + 8, counters.last)
  end

  # CTX-6 across stores: the counter is process-wide, not per store, so two stores built for two
  # tests cannot mint a colliding key.
  test "CTX-6: contexts built against two different stores never share a minted key" do
    keys = Array.new(2) do
      Dexpace::DispatchContext.build(bundle: NONE, store: Dexpace::ContextStore.new(cap: 8))
        .call_key
    end

    assert_equal(2, keys.uniq.size)
  end

  # The mint is exact under contention (design, verified fact 9): 16 threads minting 250 keys
  # each yield 4000 distinct keys. The mutex is what makes that true off CRuby.
  test "CTX-4/CTX-6: 16 threads minting concurrently never collide" do
    keys = ::Thread::Queue.new
    threads = Array.new(16) do
      ::Thread.new { 250.times { keys << Dexpace::DispatchContext.build(bundle: NONE).call_key } }
    end
    threads.each(&:join)
    minted = Array.new(4000) { keys.pop }

    assert_equal(4000, minted.uniq.size)
  end

  # CTX-2, CTX-3, CTX-7, CTX-17: what a promotion does and what construction does not.
  class PromotionTest < DexpaceTestCase
    test "CTX-17: constructing a dispatch context registers nothing" do
      store = Dexpace::ContextStore.new(cap: 8)
      ctx = Dexpace::DispatchContext.build(bundle: NONE, store: store)

      assert_equal(0, store.size)
      assert_nil(store[ctx.call_key])
    end

    test "CTX-17: a dispatch context never promoted closes as a harmless no-op" do
      store = Dexpace::ContextStore.new(cap: 8)
      ctx = Dexpace::DispatchContext.build(bundle: NONE, store: store)

      refute(ctx.close)
      assert_equal(0, store.size)
    end

    # CTX-2: assert_same, never assert_equal -- "the same InstrumentationContext reference", and
    # value equality would pass against an implementation that rebuilt the bundle. The source is
    # asserted unchanged in the same test, which is the requirement's own conformance step.
    test "CTX-2: promotion is additive, non-mutating, and carries members forward by identity" do
      store = Dexpace::ContextStore.new(cap: 8)
      source = Dexpace::DispatchContext.build(bundle: NONE, store: store)
      request = :the_request
      key_before = source.call_key

      promoted = source.promote_to_request(request: request)

      assert_instance_of(Dexpace::RequestContext, promoted)
      assert_same(source.bundle, promoted.bundle)
      assert_same(source.call_key, promoted.call_key)
      assert_same(source.store, promoted.store)
      assert_same(request, promoted.request)
      assert_nil(promoted.operation_name)
      refute_respond_to(source, :request)
      assert_same(key_before, source.call_key)
      assert_same(NONE, source.bundle)
    end

    test "CTX-2: the operation name is an argument to the dispatch->request promotion" do
      store = Dexpace::ContextStore.new(cap: 8)
      source = Dexpace::DispatchContext.build(bundle: NONE, store: store)

      promoted = source.promote_to_request(request: :req, operation_name: "GetUser")

      assert_equal("GetUser", promoted.operation_name)
      refute_respond_to(source, :operation_name)
    end

    test "CTX-17: the first promotion is the first store entry the chain ever has" do
      store = Dexpace::ContextStore.new(cap: 8)
      source = Dexpace::DispatchContext.build(bundle: NONE, store: store)

      assert_equal(0, store.size)
      promoted = source.promote_to_request(request: :req)

      assert_equal(1, store.size)
      assert_same(promoted, store[source.call_key])
    end

    # CTX-7's first clause -- "Contexts MUST be immutable and safe to share across threads
    # without external synchronization" -- which Data supplies and which nothing else asserts.
    test "CTX-7: every context flavour is frozen on construction" do
      store = Dexpace::ContextStore.new(cap: 8)
      dispatch = Dexpace::DispatchContext.build(bundle: NONE, store: store)
      request = dispatch.promote_to_request(request: :req)

      assert_predicate(dispatch, :frozen?)
      assert_predicate(request, :frozen?)
      assert_predicate(request.promote_to_exchange(response: :resp), :frozen?)
    end

    test "there is no reverse promotion: DispatchContext has no #promote_to_dispatch" do
      refute_respond_to(
        Dexpace::DispatchContext.build(bundle: NONE), :promote_to_dispatch,
      )
    end

    # #with is not a promotion and cannot be used as one: it reaches only the members its own
    # flavour declares, so #promote_to_request is the only way to add a request, which is what
    # keeps CTX-17's registration on the promotion path and off the copy path.
    test "#with cannot promote: an unknown member is refused, and a derivation keeps the key" do
      store = Dexpace::ContextStore.new(cap: 8)
      ctx = Dexpace::DispatchContext.build(bundle: NONE, store: store)

      assert_raises(ArgumentError) { ctx.with(request: :req) }
      derived = ctx.with(bundle: NONE)

      assert_same(ctx.call_key, derived.call_key)
      assert_equal(ctx, derived)
      assert_equal(0, store.size)
    end
  end

  # CTX-4 (the key's frozenness), CTX-5 (the pinned key), and the construction pattern.
  class ConstructionTest < DexpaceTestCase
    # CTX-4's key is a frozen String on both paths: minted, and pinned by a caller. Verified fact
    # 12 -- a frozen String is stored as a Hash key by identity, an unfrozen one is copied and
    # frozen on every registration -- so this is correctness and one fewer allocation.
    test "CTX-4: the call key is a frozen String whether it is minted or pinned" do
      pinned = +"shared"

      assert_predicate(Dexpace::DispatchContext.build(bundle: NONE).call_key, :frozen?)

      ctx = Dexpace::DispatchContext.build(bundle: NONE, call_key: pinned)

      assert_predicate(ctx.call_key, :frozen?)
      refute_same(pinned, ctx.call_key)
      pinned << "-mutated"

      assert_equal("shared", ctx.call_key)
    end

    test "bundle: is required with SEAM-29's message, on the minting path too" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::DispatchContext.build(bundle: nil)
      end

      assert_equal("bundle is required", error.message)
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::DispatchContext.build(bundle: nil, call_key: "pinned")
      end
      assert_equal("bundle is required", error.message)
    end

    # The .build path hands a frozen Symbol or Integer through Model.frozen_string untouched, so
    # the refusal has to come from the shared validation -- on .build and on #with alike.
    test "CTX-4: a pinned key that is not a String is refused, on .build and on #with" do
      [:sym, 5].each do |key|
        error = assert_raises(Dexpace::InvalidArgumentError, key.inspect) do
          Dexpace::DispatchContext.build(bundle: NONE, call_key: key)
        end

        assert_equal("call_key must be a String", error.message, key.inspect)
      end
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::DispatchContext.build(bundle: NONE, call_key: "pinned").with(call_key: :sym)
      end

      assert_equal("call_key must be a String", error.message)
    end

    test "an empty pinned key and a store without #set/#release are refused" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::DispatchContext.build(bundle: NONE, call_key: "")
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::DispatchContext.build(bundle: NONE, store: Object.new)
      end
    end

    test "the construction pattern: new is private and .build is the one way in" do
      refute_respond_to(Dexpace::DispatchContext, :new)
      assert_includes(Dexpace::DispatchContext.ancestors, Dexpace::Context)
      assert_equal(%i[bundle call_key store], Dexpace::DispatchContext.members)
    end
  end
end
