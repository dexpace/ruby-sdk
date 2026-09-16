# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-1: the exchange stage is terminal. Conformance: the exchange type exposes no method
# promoting back. CTX-18 and CTX-19 from the chain's side: a real Response reaches the store and
# stays reachable until the close that evicts it.
class DexpaceExchangeContextTest < DexpaceTestCase
  # The untraced bundle every case in this file builds from (CTX-15).
  NONE = Dexpace::Instrumentation::Bundle::NONE

  test "CTX-1: ExchangeContext defines no promotion method at all" do
    ctx = Dexpace::ExchangeContext.build(
      bundle: NONE, request: :req, response: :resp,
    )

    refute_respond_to(ctx, :promote_to_request)
    refute_respond_to(ctx, :promote_to_exchange)
    refute_respond_to(ctx, :promote_to_dispatch)
    assert_empty(Dexpace::ExchangeContext.public_instance_methods(false).grep(/\Apromote_to_/))
    assert_empty(Dexpace::ExchangeContext.public_instance_methods.grep(/\Apromote/))
  end

  test "an empty operation_name is rejected" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::ExchangeContext.build(
        bundle: NONE, request: :req, response: :resp,
        operation_name: "",
      )
    end
  end

  test "request: and response: are required, with SEAM-29's one message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::ExchangeContext.build(bundle: NONE, request: :req, response: nil)
    end

    assert_equal("response is required", error.message)
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::ExchangeContext.build(bundle: NONE, request: nil, response: :resp)
    end
    assert_equal("request is required", error.message)
  end

  test "CTX-18: #close on an exchange context evicts it when it is the current occupant" do
    store = Dexpace::ContextStore.new(cap: 8)
    dispatch = Dexpace::DispatchContext.build(bundle: NONE, store: store)
    exchange = dispatch.promote_to_request(request: :req).promote_to_exchange(response: :resp)

    assert(exchange.close)
    assert_nil(store[dispatch.call_key])

    refute(exchange.close)
  end

  # Builds a real phase-1 Request and a real phase-3b Response, promotes a chain over them into
  # `store`, and returns only the key: the two objects are then reachable from the store alone.
  def register_real_exchange(store)
    request_builder = Dexpace::Request.builder
    request_builder.url = "https://example.test/pets"
    request = request_builder.build
    response_builder = Dexpace::Response.builder
    response_builder.request = request
    response_builder.protocol = Dexpace::Protocol::HTTP_1_1
    response_builder.status = 200
    response_builder.body = Dexpace::ResponseBody.new(
      source: Dexpace::IO::BufferedSource.of_bytes("ok"), media_type: nil,
    )
    Dexpace::DispatchContext.build(bundle: NONE, store: store)
      .promote_to_request(request: request, operation_name: "ListPets")
      .promote_to_exchange(response: response_builder.build)
      .call_key
  end

  # CTX-19's rationale, end to end over phase 1's and 3b's real types: the registered exchange
  # context keeps its Request+Response graph -- a body included -- reachable until it is closed.
  test "CTX-19: a registered exchange context keeps a real Request and Response reachable" do
    store = Dexpace::ContextStore.new(cap: 8)
    key = register_real_exchange(store)

    3.times { GC.start }

    found = store[key]

    refute_nil(found)
    assert_equal("https://example.test/pets", found.request.url.to_s)
    assert_equal("ok", found.response.body_string)
    assert_equal("ListPets", found.operation_name)
    assert(found.close)
    assert_nil(store[key])
  end

  test "CTX-17: off-chain construction of an exchange context registers nothing" do
    store = Dexpace::ContextStore.new(cap: 8)
    ctx = Dexpace::ExchangeContext.build(
      bundle: NONE, request: :req, response: :resp, store: store,
    )

    assert_equal(0, store.size)
    refute(ctx.close)
  end

  test "the construction pattern: new is private and the members are the design's" do
    refute_respond_to(Dexpace::ExchangeContext, :new)
    assert_equal(
      %i[bundle call_key store request operation_name response],
      Dexpace::ExchangeContext.members,
    )
  end
end
