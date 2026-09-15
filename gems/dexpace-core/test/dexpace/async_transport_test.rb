# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/fake_async_transport"
require "dexpace"

# SEAM-16 and SEAM-2. A separate top-level constant and a separate registry from
# Dexpace::Transport, which the design does not name (deviation P2-1): SEAM-2 enumerates the
# synchronous and asynchronous transports as two distinct seams, so one registry keyed by kind
# would merge two concerns the requirement separates. The name is not Dexpace::Transport::Async,
# because that constant would sit beside the adapter namespaces Dexpace::Transport::NetHTTP and
# ::AsyncHTTP -- a seam beside its own implementations.
class DexpaceAsyncTransportTest < DexpaceTestCase
  CORE = "~> 0.0"

  test "conforms? has the same shape as the sync seam's, and that is an admitted gap" do
    assert(Dexpace::AsyncTransport.conforms?(FakeAsyncTransport.new))
    assert(Dexpace::AsyncTransport.conforms?(->(_r, _o, _c) {}))
    refute(Dexpace::AsyncTransport.conforms?(Object.new))
    # The two seams differ only in return type, which no predicate can check before the first
    # call. They are two registries, and an adapter names which it registers into.
    assert(Dexpace::Transport.conforms?(FakeAsyncTransport.new))
  end

  test "the registry starts empty and is not the sync seam's" do
    assert_empty(Dexpace::AsyncTransport.registered_keys)

    Dexpace::Transport.swap(->(_r, _o, _c) { :sync }) do
      assert_raises(Dexpace::SeamError) { Dexpace::AsyncTransport.resolve }
    end
  end

  test "the zero-candidate error names this seam and no gem" do
    error = assert_raises(Dexpace::SeamError) { Dexpace::AsyncTransport.resolve }

    assert_match(/no async transport provider is registered/, error.message)
    assert_match(/Dexpace::AsyncTransport\.install/, error.message)
    refute_match(/async_http|net_http/i, error.message, "SEAM-2")
  end

  test "install refuses a non-conforming object and swap scopes an override" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::AsyncTransport.install(Object.new) }

    transport = FakeAsyncTransport.new

    Dexpace::AsyncTransport.swap(transport) do
      assert_same(transport, Dexpace::AsyncTransport.resolve)
    end

    assert_raises(Dexpace::SeamError) { Dexpace::AsyncTransport.resolve }
  end

  test "install goes through the module, returns it, and is scoped by an enclosing swap" do
    transport = FakeAsyncTransport.new

    Dexpace::AsyncTransport.swap(:override) do
      assert_same(Dexpace::AsyncTransport, Dexpace::AsyncTransport.install(transport))
      assert_same(transport, Dexpace::AsyncTransport.resolve)
    end

    assert_raises(Dexpace::SeamError) { Dexpace::AsyncTransport.resolve }
  end

  # The registration is scoped inside a swap and cleaned out of the private registry afterwards,
  # for the reason transport_test.rb gives: registrations are process-global and kept by design.
  test "register goes through the module and returns the module" do
    Dexpace::AsyncTransport.swap(:override) do
      registered = Dexpace::AsyncTransport.register(:probe, -> { :p }, core: CORE)

      assert_same(Dexpace::AsyncTransport, registered)
      assert_includes(Dexpace::AsyncTransport.registered_keys, :probe)
    end
  ensure
    registry = Dexpace::AsyncTransport.const_get(:REGISTRY, false)
    state = registry.instance_variable_get(:@state)
    registry.instance_variable_set(:@state, state.with(factories: state.factories.except(:probe)))
  end

  test "a future that settles with a response is delivered, and the caller closes it" do
    response = Object.new
    transport = FakeAsyncTransport.new(response: response)

    future = transport.call(:request, nil, nil)

    assert_instance_of(Dexpace::Async::Future, future)
    assert_same(response, future.value, "SEAM-16: never a null success")
  end

  test "sync_over refuses a non-conforming transport" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::AsyncTransport.sync_over(Object.new) }
  end
end
