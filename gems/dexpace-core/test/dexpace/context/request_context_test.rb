# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-2 (the request -> exchange half), CTX-3, CTX-10, CTX-16, CTX-17.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# promotion here, CTX-16's operation name and the construction rules below.
class DexpaceRequestContextTest < DexpaceTestCase
  # The untraced bundle every case in this file builds from (CTX-15).
  NONE = Dexpace::Instrumentation::Bundle::NONE

  test "CTX-2: request -> exchange carries every source member forward by identity" do
    store = Dexpace::ContextStore.new(cap: 8)
    request = :the_request
    source = Dexpace::RequestContext.build(
      bundle: NONE, request: request,
      operation_name: "GetUser", store: store,
    )
    response = :the_response

    promoted = source.promote_to_exchange(response: response)

    assert_instance_of(Dexpace::ExchangeContext, promoted)
    assert_same(source.bundle, promoted.bundle)
    assert_same(source.call_key, promoted.call_key)
    assert_same(source.store, promoted.store)
    assert_same(source.request, promoted.request)
    assert_same(source.operation_name, promoted.operation_name)
    assert_same(response, promoted.response)
    refute_respond_to(source, :response)
  end

  test "CTX-3: the promotion overwrites the same store slot" do
    store = Dexpace::ContextStore.new(cap: 8)
    dispatch = Dexpace::DispatchContext.build(bundle: NONE, store: store)
    request_ctx = dispatch.promote_to_request(request: :req)

    assert_equal(1, store.size)
    assert_same(request_ctx, store[dispatch.call_key])

    exchange_ctx = request_ctx.promote_to_exchange(response: :resp)

    assert_equal(1, store.size)
    assert_same(exchange_ctx, store[dispatch.call_key])
    assert_same(dispatch.call_key, exchange_ctx.call_key)
  end

  # CTX-10 from the chain's side: the intermediate was promoted, so its close is a no-op and the
  # successor keeps the slot.
  test "CTX-10: closing a promoted request context is a no-op; the exchange keeps the slot" do
    store = Dexpace::ContextStore.new(cap: 8)
    request_ctx = Dexpace::DispatchContext.build(bundle: NONE, store: store)
      .promote_to_request(request: :req)
    exchange_ctx = request_ctx.promote_to_exchange(response: :resp)

    refute(request_ctx.close)
    assert_same(exchange_ctx, store[request_ctx.call_key])
    assert(exchange_ctx.close)
    assert_nil(store[request_ctx.call_key])
  end

  test "there is no reverse promotion: RequestContext has no #promote_to_dispatch" do
    refute_respond_to(
      Dexpace::RequestContext.build(bundle: NONE, request: :req),
      :promote_to_dispatch,
    )
  end

  # CTX-16: an optional operation name, carried forward unchanged, advisory only.
  class OperationNameTest < DexpaceTestCase
    # CTX-16's advisory rule, asserted as a negative: the operation name influences none of the
    # three things it is forbidden from influencing. A positive test that the name is carried
    # forward proves nothing about those three.
    test "CTX-16: operation_name changes neither the call key, the request, nor the slot" do
      store = Dexpace::ContextStore.new(cap: 8)
      request = :shared_request
      dispatch_a = Dexpace::DispatchContext.build(
        bundle: NONE, call_key: "shared", store: store,
      )
      dispatch_b = Dexpace::DispatchContext.build(
        bundle: NONE, call_key: "shared", store: store,
      )

      named = dispatch_a.promote_to_request(request: request, operation_name: "GetUser")
      unnamed = dispatch_b.promote_to_request(request: request)

      assert_equal(named.call_key, unnamed.call_key)
      assert_same(named.request, unnamed.request)
      assert_same(unnamed, store["shared"])
      assert_equal(1, store.size)
    end

    test "CTX-16: operation_name is carried forward unchanged across promotion" do
      store = Dexpace::ContextStore.new(cap: 8)
      source = Dexpace::RequestContext.build(
        bundle: NONE, request: :req,
        operation_name: "GetUser", store: store,
      )

      promoted = source.promote_to_exchange(response: :resp)

      assert_same(source.operation_name, promoted.operation_name)
    end

    test "operation_name may be absent" do
      ctx = Dexpace::RequestContext.build(bundle: NONE, request: :req)

      assert_nil(ctx.operation_name)
    end

    # CTX-16 gives exactly two states -- "GetUser", or absent -- and "" is neither.
    test "an empty operation_name is rejected, off-chain and at promotion" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::RequestContext.build(
          bundle: NONE, request: :req, operation_name: "",
        )
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::DispatchContext.build(bundle: NONE, store: Dexpace::ContextStore.new(cap: 8))
          .promote_to_request(request: :req, operation_name: "")
      end
    end

    # CTX-16's "schema-defined operation id such as 'GetUser'" is a String: a Symbol spelling of
    # the same id is refused with the field-named message, and so is anything without #empty?.
    test "a non-String operation_name is rejected, off-chain and at promotion" do
      store = Dexpace::ContextStore.new(cap: 8)

      [:GetUser, 7].each do |name|
        error = assert_raises(Dexpace::InvalidArgumentError, name.inspect) do
          Dexpace::RequestContext.build(bundle: NONE, request: :req, operation_name: name)
        end

        assert_equal("operation_name must be a String", error.message, name.inspect)
        error = assert_raises(Dexpace::InvalidArgumentError, name.inspect) do
          Dexpace::DispatchContext.build(bundle: NONE, store: store)
            .promote_to_request(request: :req, operation_name: name)
        end
        assert_equal("operation_name must be a String", error.message, name.inspect)
      end

      assert_equal(0, store.size)
    end

    test "operation_name is frozen without aliasing the caller's string" do
      name = +"GetUser"
      ctx = Dexpace::RequestContext.build(bundle: NONE, request: :req, operation_name: name)
      name << "!"

      assert_equal("GetUser", ctx.operation_name)
      assert_predicate(ctx.operation_name, :frozen?)
    end
  end

  # CTX-5, CTX-17 and the construction pattern for the middle flavour.
  class ConstructionTest < DexpaceTestCase
    test "request: is required, with SEAM-29's one message form" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::RequestContext.build(bundle: NONE, request: nil)
      end

      assert_equal("request is required", error.message)
    end

    test "CTX-17: off-chain construction of a request context registers nothing" do
      store = Dexpace::ContextStore.new(cap: 8)
      ctx = Dexpace::RequestContext.build(bundle: NONE, request: :req, store: store)

      assert_equal(0, store.size)
      refute(ctx.close)
    end

    test "CTX-5: a pinned key restores value equality between two request contexts" do
      a = Dexpace::RequestContext.build(bundle: NONE, request: :req, call_key: "shared")
      b = Dexpace::RequestContext.build(bundle: NONE, request: :req, call_key: "shared")

      assert_equal(a, b)
      refute_equal(a, Dexpace::RequestContext.build(bundle: NONE, request: :req))
    end

    test "the construction pattern: new is private and the members are the design's" do
      refute_respond_to(Dexpace::RequestContext, :new)
      assert_equal(
        %i[bundle call_key store request operation_name], Dexpace::RequestContext.members,
      )
    end
  end
end
