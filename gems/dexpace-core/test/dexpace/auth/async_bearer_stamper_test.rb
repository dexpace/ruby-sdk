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
# from one coalesced fetch, a failed or unusable background refresh logged and not fatal, the
# four provider rejections uncached (the fourth, a token the outbound header grammar refuses, is
# review round 3's R3-1), the re-entrancy trap an already-settled provider future sets,
# #stamp_fresh after an eviction, and -- the fetch being shared -- a cancellation that is not:
# cancelling one waiter detaches that waiter alone.
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

  # A request whose own derivation refuses: the one raise left inside the waiter's delivery once
  # every cached token has passed the grammar check (a forged or duck-typed request).
  class RefusingRequest
    def headers = Dexpace::Headers::EMPTY

    def with(**)
      raise Dexpace::InvalidArgumentError, "this request refuses to derive"
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

    # R3-1: the fourth rejection. Cached, a token the grammar refuses failed every later #stamp
    # until it expired and raised out of the fresh zone rather than settle; nothing could evict it.
    test "AUTH-35 async: a token the outbound header grammar refuses fails the waiters, uncached" do
      completer = Completer.new
      provider = ScriptedAsyncBearerProvider.new(completer.future,
                                                 settled_with(fresh_token("clean")),)
      subject = stamper(provider)
      waiters = Array.new(2) { subject.stamp(https_request) }
      completer.fulfil(BearerToken.build(token: "abc\n")) # a token read off a file, newline kept

      waiters.each do |waiter|
        assert_predicate(waiter, :settled?)
        error = assert_raises(Dexpace::Auth::ProviderError) { waiter.value }

        refute_match(/abc|\n/, error.message) # the message never names the token
      end
      assert_nil(subject.instance_variable_get(:@token))
      refute(subject.evict_if_matches("Bearer abc")) # nothing cached, nothing to evict
      assert_nil(subject.instance_variable_get(:@in_flight)) # the slot is free again
      later = subject.stamp(https_request) # a future, never a synchronous raise

      assert_kind_of(Dexpace::Async::Future, later)
      assert_equal(["Bearer clean"], authorization(later.value))
      assert_equal(2, provider.fetches)
    end

    test "AUTH-37: an UNUSABLE background refresh (a refused token) is logged and not cached" do
      sink = RecordingSink.new
      completer = Completer.new
      provider = ScriptedAsyncBearerProvider.new(completer.future, settled_with(fresh_token))
      subject = stamper(provider, logger: Dexpace::Instrumentation::Logger.build(sink: sink))
      subject.instance_variable_set(:@token, expiring_token)

      assert_equal(["Bearer still-valid"], authorization(subject.stamp(https_request).value))
      completer.fulfil(BearerToken.build(token: "bad\r\ntoken"))
      entry = sink.entries.find { |candidate| candidate.payload["event"] == "http.auth.refresh" }

      refute_nil(entry, sink.entries.inspect)
      assert_equal(:warn, entry.severity)
      assert_includes(entry.payload["cause"].to_s, "HTTP-18")
      refute_match(/bad|[\r\n]/, entry.payload["cause"].to_s)
      assert_equal(expiring_token, subject.instance_variable_get(:@token)) # still the valid one
      clock.advance(20) # expired now: the next stamp fetches again and succeeds

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

  # Review round 2's R2-1: the fetch is shared, a cancellation is not. Through Future#then the
  # waiter's cancellation reached the single-flight slot every coalesced caller shares, so one
  # request giving up cancelled every other waiter and every arrival until the provider settled.
  class CancellationTest < DexpaceTestCase
    include Fixtures

    test "AUTH-37, SEAM-18: cancelling one coalesced waiter detaches that waiter alone" do
      completer = Completer.new
      provider = ScriptedAsyncBearerProvider.new(completer.future)
      subject = stamper(provider)
      first = subject.stamp(https_request)
      second = subject.stamp(https_request)
      fresh = subject.stamp_fresh(https_request)
      first.cancel(:caller_gave_up)
      fresh.cancel(:caller_gave_up)

      assert_predicate(first, :cancelled?)
      assert_predicate(fresh, :cancelled?)
      refute_predicate(second, :settled?) # B never asked to be cancelled
      refute_predicate(completer.future, :settled?) # the provider's fetch runs on
      third = subject.stamp(https_request) # a new arrival still coalesces, onto a live slot

      refute_predicate(third, :settled?)
      assert_equal(1, provider.fetches)
      completer.fulfil(fresh_token)

      assert_equal(["Bearer fresh"], authorization(second.value))
      assert_equal(["Bearer fresh"], authorization(third.value))
      assert_equal(:caller_gave_up, assert_raises(Dexpace::CancelledError) { first.value }.reason)
      assert_nil(subject.instance_variable_get(:@in_flight))
      assert_equal(["Bearer fresh"], authorization(subject.stamp(https_request).value)) # cached
      assert_equal(1, provider.fetches)
    end

    test "SEAM-18: a provider cancelling its own fetch cancels every waiter, as a cancellation" do
      completer = Completer.new
      provider = ScriptedAsyncBearerProvider.new(completer.future, settled_with(fresh_token))
      subject = stamper(provider)
      waiters = Array.new(2) { subject.stamp(https_request) }
      completer.future.cancel(:provider_timeout)

      waiters.each do |waiter|
        assert_predicate(waiter, :cancelled?)
        error = assert_raises(Dexpace::CancelledError) { waiter.value }

        assert_equal(:provider_timeout, error.reason)
      end
      assert_nil(subject.instance_variable_get(:@token)) # a cancelled fetch caches nothing
      assert_nil(subject.instance_variable_get(:@in_flight)) # and the slot is free again
      assert_equal(["Bearer fresh"], authorization(subject.stamp(https_request).value))
      assert_equal(2, provider.fetches)
    end

    # Until round 3 this was a token the grammar refuses; that is now AUTH-35's fourth rejection
    # (FailureTest) and never reaches the stamp, so the raise left for #deliver's rescue to keep
    # off the settling thread is the request's own.
    test "a request whose derivation raises fails that waiter alone, never the settler" do
      completer = Completer.new
      subject = stamper(ScriptedAsyncBearerProvider.new(completer.future))
      refusing = subject.stamp(RefusingRequest.new)
      sound = subject.stamp(https_request)
      completer.fulfil(fresh_token) # settles on THIS thread: a raise in the delivery lands here

      assert_predicate(refusing, :settled?)
      assert_raises(Dexpace::InvalidArgumentError) { refusing.value }
      assert_equal(["Bearer fresh"], authorization(sound.value))
      assert_equal(["Bearer fresh"], authorization(subject.stamp(https_request).value)) # cached
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
      refute(subject.evict_if_matches("Bearer  cur")) # the exact value, as the sync half pins
      refute(subject.evict_if_matches("Bearer curator")) # a superstring is not the token sent
      refute(subject.evict_if_matches("cur"))
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
