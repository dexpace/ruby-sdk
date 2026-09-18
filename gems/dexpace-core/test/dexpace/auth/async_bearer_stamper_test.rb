# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/async_bearer_stamper"
require_relative "../../support/auth_fixtures"
require_relative "../../support/scripted_bearer_provider"
require_relative "../../support/scripted_async_bearer_provider"
require_relative "../../support/fake_clock"
require_relative "../../support/recording_sink"

# Exercises: AUTH-37, AUTH-36 (async half), AUTH-11, AUTH-35 -- the three-zone async bearer
# policy over phase 2's pivot: no #value or #wait anywhere on the stamper's own path, the
# expiring zone stamping at once while a refresh it never awaits runs, the expired zone deriving
# from one coalesced fetch, a failed background refresh logged and not fatal, the re-entrancy
# trap an already-settled provider future sets, and #stamp_fresh after an eviction.
#
# Every wait in this file is on a future the test itself settles, or on one already settled;
# a hang here would be a finding, and FakeClock never advances by itself. Split under
# Metrics/ClassLength.
class DexpaceAuthAsyncBearerStamperTest < DexpaceTestCase
  AsyncBearerStamper = Dexpace::Auth::AsyncBearerStamper
  BearerToken = Dexpace::Auth::BearerToken
  Completer = Dexpace::Async::Completer
  LIB = File.expand_path("../../../lib/dexpace/auth/async_bearer_stamper.rb", __dir__)

  # A mutex that refuses to be taken: installed on the hot path to prove it takes no lock.
  class RefusingMutex
    def synchronize
      raise "the hot path took the lock (XCUT-12)"
    end
  end

  # The stampers, tokens and futures the nested cases share. The clock reads 1000 and the
  # margin is 30, so a token expiring at 1030 or later is fresh, one expiring in (1000, 1030]
  # is expiring-but-valid, and one expiring at 1000 or earlier is expired.
  module Fixtures
    include AuthFixtures

    def clock = @clock ||= FakeClock.new(now: Time.at(1000))

    def stamper(provider, margin: 30, logger: Dexpace::Instrumentation::Logger::NULL)
      AsyncBearerStamper.new(provider: provider, clock: clock, refresh_margin: margin,
                             logger: logger,)
    end

    # A stamper whose cache already holds `token`, without a fetch.
    def seeded(provider, token)
      stamper(provider).tap { |subject| subject.instance_variable_set(:@token, token) }
    end

    def fresh_token(value = "fresh") = BearerToken.build(token: value, expiry: Time.at(2000))
    def expiring_token = BearerToken.build(token: "still-valid", expiry: Time.at(1010))
    def expired_token = BearerToken.build(token: "expired", expiry: Time.at(999))
    def no_fetch = ScriptedAsyncBearerProvider.new(-> { flunk "no fetch expected" })
    def settled_with(value) = Completer.new.tap { |c| c.fulfil(value) }.future
    def authorization(request) = request.headers["Authorization"]
  end

  # AUTH-37's three zones and the boundary between them.
  class ZonesTest < DexpaceTestCase
    include Fixtures

    test "AUTH-37 fresh: the cached token is stamped in a settled future with no provider call" do
      provider = no_fetch
      future = seeded(provider, fresh_token).stamp(https_request)

      assert_predicate(future, :settled?)
      assert_equal(["Bearer fresh"], authorization(future.value))
      assert_equal(0, provider.fetches)
    end

    test "AUTH-37, XCUT-12: the fresh zone takes no lock" do
      subject = seeded(no_fetch, fresh_token)
      subject.instance_variable_set(:@lock, RefusingMutex.new)

      assert_equal(["Bearer fresh"], authorization(subject.stamp(https_request).value))
    end

    test "AUTH-37 expiring-but-valid: stamps the cached token at once, never awaits the refresh" do
      completer = Completer.new
      provider = ScriptedAsyncBearerProvider.new(completer.future)
      subject = seeded(provider, expiring_token)
      future = subject.stamp(https_request)

      assert_predicate(future, :settled?) # returned before the refresh settled
      assert_equal(["Bearer still-valid"], authorization(future.value))
      assert_equal(1, provider.fetches)
      refute_predicate(completer, :settled?)
      completer.fulfil(fresh_token)

      assert_equal(["Bearer fresh"], authorization(subject.stamp(https_request).value))
    end

    test "AUTH-37: the zone boundary is exactly the refresh margin" do
      provider = no_fetch
      at_margin = BearerToken.build(token: "t", expiry: Time.at(1030)) # 1000 + 30, not after

      assert_predicate(seeded(provider, at_margin).stamp(https_request), :settled?)
      assert_equal(0, provider.fetches)
      counting = ScriptedAsyncBearerProvider.new(Completer.new.future)
      past_margin = BearerToken.build(token: "t", expiry: Time.at(1029))
      seeded(counting, past_margin).stamp(https_request)

      assert_equal(1, counting.fetches)
    end

    test "AUTH-37 expired/missing: the stamped request awaits the fetch, derived, not blocked" do
      completer = Completer.new
      provider = ScriptedAsyncBearerProvider.new(completer.future)
      subject = stamper(provider)
      future = subject.stamp(https_request)

      refute_predicate(future, :settled?)
      completer.fulfil(fresh_token)

      assert_predicate(future, :settled?)
      assert_equal(["Bearer fresh"], authorization(future.value))
      again = seeded(provider, expired_token).stamp(https_request) # the settled future, reused

      assert_equal(["Bearer fresh"], authorization(again.value))
    end

    test "AUTH-37: concurrent expiring and missing requests coalesce onto ONE in-flight fetch" do
      completer = Completer.new
      provider = ScriptedAsyncBearerProvider.new(completer.future)
      subject = stamper(provider)
      futures = Array.new(8) { subject.stamp(https_request) }
      subject.instance_variable_set(:@token, expiring_token)
      expiring = Array.new(4) { subject.stamp(https_request) }

      assert_equal(1, provider.fetches)
      expiring.each { |future| assert_equal(["Bearer still-valid"], authorization(future.value)) }
      completer.fulfil(fresh_token)

      futures.each { |future| assert_equal(["Bearer fresh"], authorization(future.value)) }
    end
  end

  # The failure paths: logged, uncached, retried.
  class FailureTest < DexpaceTestCase
    include Fixtures

    test "AUTH-37: a failed BACKGROUND refresh is logged and does not fail the in-flight request" do
      sink = RecordingSink.new
      completer = Completer.new
      provider = ScriptedAsyncBearerProvider.new(completer.future, settled_with(fresh_token))
      subject = stamper(provider, logger: Dexpace::Instrumentation::Logger.build(sink: sink))
      subject.instance_variable_set(:@token, expiring_token)
      request = subject.stamp(https_request).value

      assert_equal(["Bearer still-valid"], authorization(request))
      completer.fail(RuntimeError.new("refresh failed"))
      entry = sink.entries.find { |candidate| candidate.payload["event"] == "http.auth.refresh" }

      refute_nil(entry, sink.entries.inspect)
      assert_equal(:warn, entry.severity)
      assert_includes(entry.payload["cause"].to_s, "refresh failed")
      # Nothing was cached: the next stamp in the expired zone fetches again and succeeds.
      clock.advance(20)

      assert_equal(["Bearer fresh"], authorization(subject.stamp(https_request).value))
      assert_equal(2, provider.fetches)
    end

    test "AUTH-37, AUTH-35: a failed fetch is not cached, and a later request retries" do
      first = Completer.new
      provider = ScriptedAsyncBearerProvider.new(first.future, settled_with(fresh_token))
      subject = stamper(provider)
      waiting = subject.stamp(https_request)
      first.fail(RuntimeError.new("boom"))

      assert_raises(RuntimeError) { waiting.value }
      assert_equal(["Bearer fresh"], authorization(subject.stamp(https_request).value))
      assert_equal(2, provider.fetches)
    end

    test "AUTH-35 on the async path: a nil, expired or non-token result fails the waiters" do
      provider = ScriptedAsyncBearerProvider.new(settled_with(expired_token),
                                                 settled_with(Object.new),
                                                 settled_with(fresh_token),)
      subject = stamper(provider)

      assert_raises(Dexpace::Auth::ProviderError) { subject.stamp(https_request).value }
      # Caches nothing: an already-expired token is not the cached one either (round 1's R1-5).
      refute(subject.evict_if_matches("Bearer expired"))
      assert_nil(subject.instance_variable_get(:@token))
      assert_raises(Dexpace::Auth::ProviderError) { subject.stamp(https_request).value }
      assert_nil(subject.instance_variable_get(:@token))
      assert_equal(["Bearer fresh"], authorization(subject.stamp(https_request).value))
      nil_token = stamper(ScriptedBearerProvider.new(-> {}))

      assert_raises(Dexpace::Auth::ProviderError) { nil_token.stamp(https_request).value }
      assert_nil(nil_token.instance_variable_get(:@token))
    end

    # The regression R12 exists to prevent: AUTH-11's default wrapper mirrors a #fetch-only
    # provider into an ALREADY-SETTLED future, whose #on_settle runs inline on the calling fiber;
    # started under @lock, the settle block's own synchronize would raise
    # `ThreadError: deadlock; recursive locking`.
    test "AUTH-11, R12: a #fetch-only provider's already-settled future does not deadlock" do
      subject = stamper(ScriptedBearerProvider.new("sync"))
      future = subject.stamp(https_request)

      assert_predicate(future, :settled?)
      assert_equal(["Bearer sync"], authorization(future.value))
      assert_equal(["Bearer sync"], authorization(subject.stamp_fresh(https_request).value))
    end

    test "AUTH-11: a #fetch_async override that raises synchronously fails the future, uncached" do
      provider = ScriptedAsyncBearerProvider.new(ArgumentError.new("misbehaving"),
                                                 settled_with(fresh_token),)
      subject = stamper(provider)

      assert_raises(ArgumentError) { subject.stamp(https_request).value }
      assert_equal(["Bearer fresh"], authorization(subject.stamp(https_request).value))
    end
  end

  # AUTH-36's async half, AUTH-37's post-eviction clause, and the construction checks.
  class EvictionTest < DexpaceTestCase
    include Fixtures

    test "AUTH-37's post-eviction clause: #stamp_fresh never stamps the cache, always a fetch" do
      provider = ScriptedAsyncBearerProvider.new(-> { settled_with(fresh_token("fetched")) })
      subject = seeded(provider, fresh_token("cached"))

      assert_equal(["Bearer fetched"], authorization(subject.stamp_fresh(https_request).value))
      assert_equal(1, provider.fetches)
      assert_equal(["Bearer fetched"], authorization(subject.stamp(https_request).value))
      assert_equal(1, provider.fetches) # now cached
    end

    test "AUTH-36 async half: eviction on the exact header value, a refreshed token preserved" do
      subject = seeded(no_fetch, fresh_token("cur"))

      refute(subject.evict_if_matches("Bearer stale"))
      assert_equal(["Bearer cur"], authorization(subject.stamp(https_request).value))
      assert(subject.evict_if_matches("Bearer cur"))
      refute(subject.evict_if_matches("Bearer cur"))
    end

    test "R12 as code: the stamper's own path calls neither #value nor #wait" do
      refute_match(/\.value\b|\.wait\b|Async\.delay/, File.read(LIB))
    end

    test "the provider must answer #fetch; the margin and logger are validated" do
      provider = ScriptedBearerProvider.new("t")

      assert_raises(Dexpace::InvalidArgumentError) { stamper(Object.new) }
      assert_raises(Dexpace::InvalidArgumentError) { stamper(provider, margin: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { stamper(provider, logger: nil) }
    end
  end
end
