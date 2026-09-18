# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/bearer_provider"
require_relative "../../support/scripted_bearer_provider"
require_relative "../../support/scripted_async_bearer_provider"

# Exercises: AUTH-11 -- the provider duck type and its default async fetch: a #fetch-only
# provider mirrored into an already-settled future (success and failure alike), a #fetch_async
# override's synchronous raise normalised into a failed future, a nil token and a non-Future
# return each a failed future, and a genuine future passed through untouched.
class DexpaceAuthBearerProviderTest < DexpaceTestCase
  BearerProvider = Dexpace::Auth::BearerProvider
  BearerToken = Dexpace::Auth::BearerToken

  test "AUTH-11: #fetch is the one required method" do
    assert(BearerProvider.conforms?(ScriptedBearerProvider.new("t")))
    assert(BearerProvider.conforms?(ScriptedAsyncBearerProvider.new("t")))
    refute(BearerProvider.conforms?(Object.new))
  end

  test "AUTH-11: a #fetch-only provider's success is mirrored into an already-settled future" do
    future = BearerProvider.fetch_async(ScriptedBearerProvider.new("tok"))

    assert_predicate(future, :settled?)
    assert_equal("tok", future.value.token)
  end

  test "AUTH-11: a #fetch-only provider's raise is mirrored into an already-FAILED future" do
    future = BearerProvider.fetch_async(ScriptedBearerProvider.new(RuntimeError.new("boom")))

    assert_predicate(future, :settled?)
    error = assert_raises(RuntimeError) { future.value }

    assert_equal("boom", error.message)
  end

  test "AUTH-35 through AUTH-11: a nil token from #fetch never reaches Completer#fulfil" do
    future = BearerProvider.fetch_async(ScriptedBearerProvider.new(-> {}))

    assert_predicate(future, :settled?)
    assert_raises(Dexpace::Auth::ProviderError) { future.value }
  end

  test "AUTH-11: a genuine #fetch_async future is returned as it is, settled or not" do
    completer = Dexpace::Async::Completer.new
    future = BearerProvider.fetch_async(ScriptedAsyncBearerProvider.new(completer.future))

    assert_same(completer.future, future)
    refute_predicate(future, :settled?)
    completer.fulfil(BearerToken.build(token: "t"))

    assert_equal("t", future.value.token)
  end

  test "AUTH-11: a misbehaving #fetch_async that raises synchronously is a failed future" do
    provider = ScriptedAsyncBearerProvider.new(ArgumentError.new("misbehaving"))
    future = BearerProvider.fetch_async(provider)

    assert_predicate(future, :settled?)
    assert_raises(ArgumentError) { future.value }
  end

  test "AUTH-11: a #fetch_async that returns something other than a Future is a failed future" do
    provider = ScriptedAsyncBearerProvider.new(BearerToken.build(token: "t"))
    future = BearerProvider.fetch_async(provider)

    error = assert_raises(Dexpace::Auth::ProviderError) { future.value }

    assert_includes(error.message, "not a Dexpace::Async::Future")
  end

  test "the module holds no state" do
    assert_empty(BearerProvider.instance_variables)
  end
end
