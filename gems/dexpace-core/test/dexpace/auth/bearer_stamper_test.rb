# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/bearer_stamper"
require_relative "../../support/auth_fixtures"
require_relative "../../support/scripted_bearer_provider"
require_relative "../../support/fake_clock"

# Exercises: AUTH-11 (sync half), AUTH-34, AUTH-35, AUTH-36 (the cache half) -- the sync bearer
# stamper: the cached token stamped until the refresh margin, a lock-free hot path, at most one
# fetch under sixteen racing threads, the three provider rejections uncached, and the
# compare-and-clear eviction on the stamped header value.
class DexpaceAuthBearerStamperTest < DexpaceTestCase
  include AuthFixtures

  BearerStamper = Dexpace::Auth::BearerStamper
  BearerToken = Dexpace::Auth::BearerToken

  # A mutex that refuses to be taken: installed on the hot path to prove it takes no lock.
  class RefusingMutex
    def synchronize
      raise "the hot path took the lock (XCUT-12)"
    end
  end

  def stamper(provider, clock: FakeClock.new, margin: 30)
    BearerStamper.new(provider: provider, clock: clock, refresh_margin: margin)
  end

  def authorization(request) = request.headers["Authorization"]

  test "AUTH-34: stamps Authorization: Bearer <token>, SET rather than added" do
    already = https_request(headers: Dexpace::Headers.builder.add("Authorization", "old").build)
    subject = stamper(ScriptedBearerProvider.new("t1"))

    assert_equal(["Bearer t1"], authorization(subject.call(https_request)))
    assert_equal(["Bearer t1"], authorization(subject.call(already)))
  end

  test "AUTH-34: the token is cached until the refresh margin before its expiry, 30 s by default" do
    clock = FakeClock.new(now: Time.at(0))
    provider = ScriptedBearerProvider.new(BearerToken.build(token: "t1", expiry: Time.at(100)),
                                          BearerToken.build(token: "t2", expiry: Time.at(300)),)
    subject = stamper(provider, clock: clock)
    subject.call(https_request)
    clock.advance(69) # 69 + 30 = 99, not after 100: still cached

    assert_equal(["Bearer t1"], authorization(subject.call(https_request)))
    assert_equal(1, provider.fetches)
    clock.advance(2) # 71 + 30 = 101: refreshed

    assert_equal(["Bearer t2"], authorization(subject.call(https_request)))
    assert_equal(2, provider.fetches)
    assert_equal(30, BearerStamper::DEFAULT_REFRESH_MARGIN)
  end

  test "AUTH-34, XCUT-12: the hot-path read of a valid cached token takes no lock" do
    subject = stamper(ScriptedBearerProvider.new("t1"))
    subject.call(https_request)
    subject.instance_variable_set(:@lock, RefusingMutex.new)

    assert_equal(["Bearer t1"], authorization(subject.call(https_request)))
  end

  # Deterministic: the one fetch parks until all sixteen threads have entered #call, so every
  # other thread is racing on the missing token while it is in flight.
  test "AUTH-34: sixteen threads racing on a missing token cause exactly one fetch" do
    arrived = ::Thread::Queue.new
    provider = ScriptedBearerProvider.new("t1").before_fetch do
      Thread.pass until arrived.size == 16
    end
    subject = stamper(provider)
    threads = Array.new(16) do
      Thread.new do
        arrived << true
        authorization(subject.call(https_request))
      end
    end

    assert_equal([["Bearer t1"]] * 16, threads.map(&:value))
    assert_equal(1, provider.fetches)
  end

  test "AUTH-35: a nil token surfaces as ProviderError and is not cached" do
    provider = ScriptedBearerProvider.new(-> {}, "t2")
    subject = stamper(provider)

    assert_raises(Dexpace::Auth::ProviderError) { subject.call(https_request) }
    assert_equal(["Bearer t2"], authorization(subject.call(https_request)))
    assert_equal(2, provider.fetches)
  end

  test "AUTH-35: a token already expired at fetch time, evaluated with NO margin, is an error" do
    clock = FakeClock.new(now: Time.at(100))
    provider = ScriptedBearerProvider.new(BearerToken.build(token: "old", expiry: Time.at(99)),
                                          BearerToken.build(token: "edge", expiry: Time.at(100)),)
    subject = stamper(provider, clock: clock)

    assert_raises(Dexpace::Auth::ProviderError) { subject.call(https_request) }
    # expiry == now is NOT expired with no margin (strictly after), so it is accepted, then
    # the margin makes it a refresh candidate on the next call.
    assert_equal(["Bearer edge"], authorization(subject.call(https_request)))
  end

  test "AUTH-35: something that is not a BearerToken is an error" do
    assert_raises(Dexpace::Auth::ProviderError) do
      stamper(ScriptedBearerProvider.new(-> { Object.new })).call(https_request)
    end
  end

  test "AUTH-35, AUTH-11: a raising provider propagates its own error, uncached; next retries" do
    provider = ScriptedBearerProvider.new(RuntimeError.new("boom"), "t2")
    subject = stamper(provider)

    error = assert_raises(RuntimeError) { subject.call(https_request) }

    assert_equal("boom", error.message)
    assert_equal(["Bearer t2"], authorization(subject.call(https_request)))
  end

  test "AUTH-36: eviction clears only the exact rejected header value, and the next call fetches" do
    provider = ScriptedBearerProvider.new("old", "new")
    subject = stamper(provider)
    subject.call(https_request)

    assert(subject.evict_if_matches("Bearer old"))
    assert_equal(["Bearer new"], authorization(subject.call(https_request)))
    assert_equal(2, provider.fetches)
  end

  test "AUTH-36: a token another request already refreshed does not match and is preserved" do
    provider = ScriptedBearerProvider.new("current")
    subject = stamper(provider)
    subject.call(https_request)

    refute(subject.evict_if_matches("Bearer stale"))
    refute(subject.evict_if_matches("Bearer  current")) # matched on the exact header value
    assert_equal(["Bearer current"], authorization(subject.call(https_request)))
    assert_equal(1, provider.fetches)
    refute(stamper(provider).evict_if_matches("Bearer current")) # nothing cached yet
  end

  test "the provider must answer #fetch and the margin must be a non-negative number" do
    assert_raises(Dexpace::InvalidArgumentError) { stamper(Object.new) }
    provider = ScriptedBearerProvider.new("t")

    assert_raises(Dexpace::InvalidArgumentError) { stamper(provider, margin: -1) }
    assert_raises(Dexpace::InvalidArgumentError) { stamper(provider, margin: "30") }
  end
end
