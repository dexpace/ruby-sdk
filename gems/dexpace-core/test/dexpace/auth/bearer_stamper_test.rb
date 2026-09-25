# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/bearer_stamper"
require_relative "../../support/auth_fixtures"
require_relative "../../support/scripted_bearer_provider"
require_relative "../../support/fake_clock"

# Exercises: AUTH-11 (sync half), AUTH-34, AUTH-35, AUTH-36 (the cache half) -- the sync bearer
# stamper: the cached token stamped until the refresh margin, a lock-free hot path, at most one
# fetch under sixteen racing threads, the four provider rejections uncached (the fourth, a token
# the outbound header grammar refuses, is review round 3's R3-1), and the compare-and-clear
# eviction on the stamped header value. Split under Metrics/ClassLength.
class DexpaceAuthBearerStamperTest < DexpaceTestCase
  BearerStamper = Dexpace::Auth::BearerStamper
  BearerToken = Dexpace::Auth::BearerToken

  # A mutex that refuses to be taken: installed on the hot path to prove it takes no lock.
  class RefusingMutex
    def synchronize
      raise "the hot path took the lock (XCUT-12)"
    end
  end

  # The stamper and the reader the nested cases share.
  module Fixtures
    include AuthFixtures

    def stamper(provider, clock: FakeClock.new, margin: 30)
      BearerStamper.new(provider: provider, clock: clock, refresh_margin: margin)
    end

    def authorization(request) = request.headers["Authorization"]
  end

  # AUTH-34: the stamp, the cache and its margin, the lock-free hot path, single flight.
  class CacheTest < DexpaceTestCase
    include Fixtures

    test "AUTH-34: stamps Authorization: Bearer <token>, SET rather than added" do
      already = https_request(headers: Dexpace::Headers.builder.add("Authorization", "old").build)
      subject = stamper(ScriptedBearerProvider.new("t1"))

      assert_equal(["Bearer t1"], authorization(subject.call(https_request)))
      assert_equal(["Bearer t1"], authorization(subject.call(already)))
    end

    test "AUTH-34: the token is cached until the refresh margin before expiry, 30 s by default" do
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
  end

  # AUTH-35: the four provider rejections and a raising provider, none of them cached.
  class RejectionTest < DexpaceTestCase
    include Fixtures

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

    # R3-1: a token read off a file with its newline, a CR, a non-ASCII byte -- none can ever be
    # sent, so no 401 could ever evict one (AUTH-36); cached, it would fail every call until it
    # expired, which for a token with no expiry is never.
    test "AUTH-35: a token the outbound header grammar refuses is an error, uncached; refetched" do
      provider = ScriptedBearerProvider.new("abc\n", "bad\r\ntoken", "t\u00f6ken", "clean")
      subject = stamper(provider)

      3.times do
        error = assert_raises(Dexpace::Auth::ProviderError) { subject.call(https_request) }

        refute_match(/abc|bad|\u00f6|[\r\n]/, error.message) # the message never names the token
        assert_nil(subject.instance_variable_get(:@token))
      end
      refute(subject.evict_if_matches("Bearer abc")) # nothing cached, nothing to evict
      assert_equal(["Bearer clean"], authorization(subject.call(https_request)))
      assert_equal(4, provider.fetches)
    end

    # 6c's review R4-1, pinned by phase 10: every rejection above starts from a COLD cache, so a
    # stamper that validated only a first fetch and skipped the check when REFRESHING a cached
    # token survived three mutations. Each rejection again, from a warm cache past its margin: the
    # error surfaces, the cached token is left exactly as it was, and the next call refetches.
    test "AUTH-35: every rejection holds on the REFRESH path too, the warm cache untouched" do
      [-> {}, -> { Object.new }, "bad\r\ntoken"].each do |rejected|
        clock = FakeClock.new(now: Time.at(0))
        warm = BearerToken.build(token: "t1", expiry: Time.at(100))
        provider = ScriptedBearerProvider.new(warm, rejected, "t3")
        subject = stamper(provider, clock: clock)
        subject.call(https_request)
        clock.advance(80) # inside the 30 s margin: the next call refreshes

        assert_raises(Dexpace::Auth::ProviderError) { subject.call(https_request) }
        assert_same(warm, subject.instance_variable_get(:@token), "the cache was touched")
        assert_equal(["Bearer t3"], authorization(subject.call(https_request)))
      end
    end

    test "AUTH-35, AUTH-11: a raising provider propagates its own error, uncached; next retries" do
      provider = ScriptedBearerProvider.new(RuntimeError.new("boom"), "t2")
      subject = stamper(provider)

      error = assert_raises(RuntimeError) { subject.call(https_request) }

      assert_equal("boom", error.message)
      assert_equal(["Bearer t2"], authorization(subject.call(https_request)))
    end
  end

  # AUTH-36's cache half, and the construction checks.
  class EvictionTest < DexpaceTestCase
    include Fixtures

    test "AUTH-36: eviction clears only the exact rejected header value; the next call fetches" do
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
end
