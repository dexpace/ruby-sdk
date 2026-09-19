# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/async_step"
require_relative "../../../lib/dexpace/auth/async_bearer_stamper"
require_relative "../../../lib/dexpace/auth/key_stamper"
require_relative "../../../lib/dexpace/auth/key_credential"
require_relative "../../support/auth_fixtures"
require_relative "../../support/scripted_bearer_provider"
require_relative "../../support/scripted_async_bearer_provider"
require_relative "../../support/spy_cursor"
require_relative "../../support/spy_bearer_stamper"
require_relative "../../support/fake_clock"

# Exercises: AUTH-38 and the async mirror of AUTH-27 through AUTH-37 -- the async AUTH pillar
# step through a real async pipeline: every failure a failed future and never a synchronous
# raise, the three-zone stamper driven through it, the bearer 401 branch awaiting a genuinely
# fresh fetch after an eviction and reusing a preserved token otherwise -- the routing itself
# through a stamper double whose #stamp and #stamp_fresh differ on the wire (review round 0's
# R0-1), since the real stamper fetches either way once its cache is empty -- AUTH-31's gate
# through the inherited predicate, AUTH-32's three clauses, cancellation forwarded both ways,
# one request's cancellation reaching no other request coalesced on the same bearer fetch, and
# a provider token the header grammar refuses failing the requests that awaited it and no
# later one (review round 3's R3-1). Every #value here is on a future the test settles or one
# already settled. Split under Metrics/ClassLength.
class DexpaceAuthAsyncStepTest < DexpaceTestCase
  AsyncStep = Dexpace::Auth::AsyncStep
  Step = Dexpace::Auth::Step
  STAGES = Dexpace::Pipeline::Stages
  Completer = Dexpace::Async::Completer
  LIB = File.expand_path("../../../lib/dexpace/auth/async_step.rb", __dir__)

  # The steps, stampers and async pipelines the nested cases share.
  module Fixtures
    include AuthFixtures

    def key_stamper(key = "secret")
      Dexpace::Auth::KeyStamper.new(Dexpace::Auth::KeyCredential.new(api_key: key))
    end

    def async_step(stamper: key_stamper, hook: Step::NO_REPLACEMENT)
      AsyncStep.build(stamper: stamper, challenge_hook: hook)
    end

    def clock = @clock ||= FakeClock.new(now: Time.at(1000))

    def async_bearer(*tokens)
      Dexpace::Auth::AsyncBearerStamper.new(provider: ScriptedBearerProvider.new(*tokens),
                                            clock: clock,)
    end

    def async_bearer_over(provider)
      Dexpace::Auth::AsyncBearerStamper.new(provider: provider, clock: clock)
    end

    def dispatch(step, transport, request = https_request, redirect_state: nil, stage: nil)
      builder = Dexpace::Pipeline::Builder.new(transport: transport)
      unless redirect_state.nil?
        builder.append(ForkingProbe.new(times: 1, state_per_drive: [redirect_state]),
                       stage: STAGES::REDIRECT,)
      end
      stage.nil? ? builder.append(step) : builder.append(step, stage: stage)
      builder.build_async.call(request)
    end

    def settled(*script) = SequencedAsyncTransport.new(*script)
  end

  # AUTH-38 and R12: the one Completer frame.
  class FrameTest < DexpaceTestCase
    include Fixtures

    test "P5-34's shape: an AsyncStep is a Step with the same stage, .build and private .new" do
      step = async_step

      assert_kind_of(Step, step)
      assert_same(STAGES::AUTH, step.stage)
      assert_predicate(step, :frozen?)
      refute_respond_to(AsyncStep, :new)
    end

    test "the stamper may answer #stamp (async) or #call (adapted); anything else is refused" do
      AsyncStep.build(stamper: async_bearer("t"))
      AsyncStep.build(stamper: key_stamper)

      assert_raises(Dexpace::InvalidArgumentError) { AsyncStep.build(stamper: Object.new) }
      assert_raises(Dexpace::InvalidArgumentError) { Step.build(stamper: async_bearer("t")) }
    end

    test "AUTH-38: the HTTPS guard's failure is a failed future, never a synchronous raise" do
      future = dispatch(async_step, settled(ok), http_request)

      assert_kind_of(Dexpace::Async::Future, future)
      assert_predicate(future, :settled?)
      error = assert_raises(Dexpace::Auth::HTTPSRequiredError) { future.value }

      assert_equal("Dexpace::Auth::AsyncStep", error.step)
    end

    test "AUTH-38: a stamper that raises, or a provider that fails, is a failed future" do
      raising = ->(_request) { raise "stamper blew up" }

      assert_raises(RuntimeError) { dispatch(async_step(stamper: raising), settled(ok)).value }
      failing = async_bearer_over(ScriptedBearerProvider.new(RuntimeError.new("fetch failed")))
      future = dispatch(async_step(stamper: failing), settled(ok))

      assert_predicate(future, :settled?)
      assert_raises(RuntimeError) { future.value }
    end

    # The driver normalises a synchronously raising step into a failed future (PIPE-30), so
    # through a pipeline the frame cannot be told from the driver: this calls the step directly,
    # on a root cursor, where nothing but the step's own frame stands between a raise and the
    # caller.
    test "AUTH-38: called directly, outside the driver, the guard's failure is a failed future" do
      cursor = Dexpace::Pipeline::Cursor.build(drive: Object.new, request: http_request,
                                               options: Dexpace::RequestOptions::EMPTY,
                                               cancellation: Dexpace::Cancellation.none,)
      future = async_step.call(http_request, cursor)

      assert_kind_of(Dexpace::Async::Future, future)
      assert_raises(Dexpace::Auth::HTTPSRequiredError) { future.value }
      raising = async_step(stamper: ->(_request) { raise "stamper blew up" })
      secure = Dexpace::Pipeline::Cursor.build(drive: Object.new, request: https_request,
                                               options: Dexpace::RequestOptions::EMPTY,
                                               cancellation: Dexpace::Cancellation.none,)

      assert_raises(RuntimeError) { raising.call(https_request, secure).value }
    end

    test "R12: with no Fiber.scheduler the step still returns a future and never delays" do
      refute(Fiber.scheduler)
      refute_match(/\.value\b|\.wait\b|Async\.delay|Fiber\.scheduler/, File.read(LIB))
      assert_kind_of(Dexpace::Async::Future, dispatch(async_step, settled(ok)))
    end
  end

  # AUTH-27, AUTH-29, AUTH-37 and SEAM-18 on the async path.
  class DriveTest < DexpaceTestCase
    include Fixtures

    test "AUTH-27, P4-39: the stamped request drives a fresh fork; the handed cursor not called" do
      spy = nil
      step = async_step
      wrapper = ->(request, cursor) { step.call(request, spy = SpyCursor.new(cursor)) }
      transport = settled(ok)
      response = dispatch(wrapper, transport, stage: STAGES::AUTH).value

      assert_equal(200, response.status.code)
      assert_equal(["secret"], transport.authorization_headers)
      assert_equal(1, spy.forks)
      assert_equal(0, spy.calls)
    end

    test "AUTH-29: cross-origin is neither guarded nor stamped; same-origin and none are stamped" do
      transport = settled(ok)
      no_stamp = async_step(stamper: ->(_r) { flunk "no stamp cross-origin" })
      response = dispatch(no_stamp, transport, http_request,
                          redirect_state: { cross_origin: true },).value

      assert_equal(200, response.status.code)
      assert_equal([nil], transport.authorization_headers)
      same = settled(ok)
      dispatch(async_step, same, redirect_state: { cross_origin: false }).value

      assert_equal(["secret"], same.authorization_headers)
      none = settled(ok)
      dispatch(async_step, none).value

      assert_equal(["secret"], none.authorization_headers)
    end

    test "AUTH-37 through the step: the expired zone awaits the fetch before the drive" do
      completer = Completer.new
      stamper = async_bearer_over(ScriptedAsyncBearerProvider.new(completer.future))
      transport = settled(ok)
      future = dispatch(async_step(stamper: stamper), transport)

      refute_predicate(future, :settled?)
      assert_empty(transport.calls)
      completer.fulfil(Dexpace::Auth::BearerToken.build(token: "fresh"))

      assert_equal(200, future.value.status.code)
      assert_equal(["Bearer fresh"], transport.authorization_headers)
    end

    test "a transport failure on any drive fails the step's future with the same object" do
      boom = RuntimeError.new("transport failed")
      failed = dispatch(async_step, settled(boom))

      assert_same(boom, assert_raises(RuntimeError) { failed.value })
      cross = dispatch(async_step, settled(boom), http_request,
                       redirect_state: { cross_origin: true },)

      assert_same(boom, assert_raises(RuntimeError) { cross.value })
    end

    test "a transport whose future settles later settles the step's future then, and not before" do
      held = Completer.new
      transport = settled(held.future)
      future = dispatch(async_step, transport)

      refute_predicate(future, :settled?)
      held.fulfil(ok)

      assert_equal(200, future.value.status.code)
    end

    test "SEAM-18: cancelling the returned future cancels the in-flight drive, as a cancellation" do
      held = Completer.new
      future = dispatch(async_step, settled(held.future))
      future.cancel(:stop)

      assert_predicate(held.future, :cancelled?)
      assert_predicate(future, :cancelled?)
      inner = Completer.new
      forwarded = dispatch(async_step, settled(inner.future))
      inner.request_cancel(:gone)

      assert_predicate(forwarded, :cancelled?)
      assert_equal(:gone, assert_raises(Dexpace::CancelledError) { forwarded.value }.reason)
    end
  end

  # AUTH-30 through AUTH-33 on the async path, the hook's future form included.
  class ChallengeTest < DexpaceTestCase
    include Fixtures

    test "AUTH-30: a 401 with a challenge consults the hook and replays the replacement once" do
      first = unauthorized("Basic realm=r")
      closed_at_replay = nil
      replay = lambda do |_request|
        closed_at_replay = closes_of(first) # read AS the replay reaches the transport (R1-2)
        ok
      end
      transport = settled(first, replay)
      response = dispatch(async_step(hook: ->(_c, request, _r) { request }), transport).value

      assert_equal(200, response.status.code)
      assert_equal(2, transport.calls.size)
      assert_equal(1, closed_at_replay) # the 401 is closed BEFORE the replay drives
      assert_equal(0, closes_of(response))
    end

    test "AUTH-30: the default hook yields no replacement; AUTH-33: no challenge, no consulting" do
      consulted = false
      first = unauthorized(nil)
      hook = lambda do |*|
        consulted = true
        nil
      end
      response = dispatch(async_step(hook: hook), settled(first, ok)).value

      assert_same(first, response)
      refute(consulted)
      default = dispatch(async_step, settled(unauthorized("Basic realm=r"), ok)).value

      assert_equal(401, default.status.code)
    end

    test "AUTH-30, AUTH-32: a hook may answer a FUTURE of a replacement, awaited, not blocked on" do
      pending = Completer.new
      transport = settled(unauthorized("Basic realm=r"), ok)
      future = dispatch(async_step(hook: ->(*) { pending.future }), transport)

      refute_predicate(future, :settled?)
      pending.fulfil(https_request)

      assert_equal(200, future.value.status.code)
    end

    test "AUTH-32: a hook that raises synchronously closes the 401 and fails the future" do
      first = unauthorized("Basic realm=r")
      future = dispatch(async_step(hook: ->(*) { raise "hook blew up" }), settled(first, ok))

      assert_raises(RuntimeError) { future.value }
      assert_equal(1, closes_of(first))
    end

    test "AUTH-32: a hook whose future completes exceptionally closes the 401, fails the future" do
      first = unauthorized("Basic realm=r")
      pending = Completer.new
      future = dispatch(async_step(hook: ->(*) { pending.future }), settled(first, ok))
      pending.fail(RuntimeError.new("async hook failed"))

      assert_raises(RuntimeError) { future.value }
      assert_equal(1, closes_of(first))
    end

    test "AUTH-32: a hook answering a non-request closes the 401 and fails the future" do
      first = unauthorized("Basic realm=r")
      future = dispatch(async_step(hook: ->(*) { "junk" }), settled(first, ok))

      assert_raises(Dexpace::InvalidArgumentError) { future.value }
      assert_equal(1, closes_of(first))
    end

    # Round 1's R1-1: the settled value was checked outside the closing frame, so this shape
    # failed the future with the 401 left open; a future of a future is the same clause.
    test "AUTH-32: a hook FUTURE fulfilling with a non-request closes the 401, fails the future" do
      inner = Completer.new.tap { |completer| completer.fulfil(https_request) }.future
      ["junk", inner].each do |value|
        first = unauthorized("Basic realm=r")
        hook = ->(*) { Completer.new.tap { |completer| completer.fulfil(value) }.future }
        future = dispatch(async_step(hook: hook), settled(first, ok))
        error = assert_raises(Dexpace::InvalidArgumentError) { future.value }

        assert_includes(error.message, "got #{value.class}")
        assert_equal(1, closes_of(first))
      end
    end

    test "AUTH-31 on the async path: a non-replayable replacement surfaces the 401 unclosed" do
      first = unauthorized("Basic realm=r")
      transport = settled(first, ok)
      hook = ->(*) { post_request(replayable: false) }
      response = dispatch(async_step(hook: hook), transport, post_request).value

      assert_same(first, response)
      assert_equal(0, closes_of(first))
      assert_equal(1, transport.calls.size)
    end
  end

  # AUTH-36 and AUTH-37's post-eviction clause on the async path.
  class BearerTest < DexpaceTestCase
    include Fixtures

    test "AUTH-36, AUTH-37: the bearer 401 branch awaits a fresh fetch, never re-sends the token" do
      stamper = async_bearer("old", "new")
      first = unauthorized_bearer
      closed_at_retry = nil
      retry_reply = lambda do |_request|
        closed_at_retry = closes_of(first)
        ok
      end
      transport = settled(first, retry_reply)
      response = dispatch(async_step(stamper: stamper), transport).value

      assert_equal(200, response.status.code)
      assert_equal(["Bearer old", "Bearer new"], transport.authorization_headers)
      assert_equal(1, closed_at_retry) # the superseded 401 is closed BEFORE the retry drives
    end

    test "AUTH-36: a token another request refreshed is preserved and reused, no fetch" do
      provider = ScriptedBearerProvider.new("old", "never")
      stamper = async_bearer_over(provider)
      refreshed = Dexpace::Auth::BearerToken.build(token: "refreshed-elsewhere")
      swap = lambda do |_request|
        stamper.instance_variable_set(:@token, refreshed)
        unauthorized_bearer
      end
      transport = settled(swap, ok)
      dispatch(async_step(stamper: stamper), transport).value

      assert_equal(["Bearer old", "Bearer refreshed-elsewhere"], transport.authorization_headers)
      assert_equal(1, provider.fetches)
    end

    test "AUTH-36: cross-origin suppression and a non-Bearer challenge surface the 401 unchanged" do
      first = unauthorized_bearer
      response = dispatch(async_step(stamper: async_bearer("old")), settled(first, ok),
                          redirect_state: { cross_origin: true },).value

      assert_same(first, response)
      basic = unauthorized("Basic realm=r")

      assert_same(basic,
                  dispatch(async_step(stamper: async_bearer("old")), settled(basic, ok)).value,)
    end

    test "AUTH-31, P6-7: a non-replayable body skips the bearer retry on the async path too" do
      first = unauthorized_bearer
      transport = settled(first, ok)
      response = dispatch(async_step(stamper: async_bearer("old", "new")), transport,
                          post_request(replayable: false),).value

      assert_same(first, response)
      assert_equal(0, closes_of(first))
    end

    test "AUTH-35: a provider that fails on the post-eviction fetch fails the future, 401 closed" do
      first = unauthorized_bearer
      stamper = async_bearer("old", RuntimeError.new("refresh failed"))
      future = dispatch(async_step(stamper: stamper), settled(first, ok))

      assert_equal("refresh failed", assert_raises(RuntimeError) { future.value }.message)
      assert_equal(1, closes_of(first))
    end

    test "a sync BearerStamper installed on the async step is adapted and still retries" do
      stamper = Dexpace::Auth::BearerStamper.new(provider: ScriptedBearerProvider.new("old", "new"),
                                                 clock: clock,)
      transport = settled(unauthorized_bearer, ok)

      assert_equal(200, dispatch(async_step(stamper: stamper), transport).value.status.code)
      assert_equal(["Bearer old", "Bearer new"], transport.authorization_headers)
    end

    # The real stamper fetches through either method once evicted, so only a double whose two
    # stamps differ on the wire can tell the routing apart (R0-1).
    test "AUTH-37: after a SUCCESSFUL eviction the retry goes through #stamp_fresh, never #stamp" do
      stamper = SpyBearerStamper.new(evicts: true)
      transport = settled(unauthorized_bearer, ok)
      response = dispatch(async_step(stamper: stamper), transport).value

      assert_equal(200, response.status.code)
      assert_equal(["Bearer cached", "Bearer fresh"], transport.authorization_headers)
      assert_equal([:stamp, [:evict_if_matches, "Bearer cached"], :stamp_fresh], stamper.calls)
    end

    test "AUTH-36: after a FAILED eviction (refreshed elsewhere) the retry is stamped by #stamp" do
      stamper = SpyBearerStamper.new(evicts: false)
      transport = settled(unauthorized_bearer, ok)
      response = dispatch(async_step(stamper: stamper), transport).value

      assert_equal(200, response.status.code)
      assert_equal(["Bearer cached", "Bearer cached"], transport.authorization_headers)
      assert_equal([:stamp, [:evict_if_matches, "Bearer cached"], :stamp], stamper.calls)
    end
  end

  # The single-flight fetch through the pipeline. Review round 2's R2-1: the step forwards its
  # future's cancellation to the stamp future (P6-79), and that must stop at the one request's
  # waiter, never reach the fetch the other requests share. Review round 3's R3-1: a fetch that
  # lands a token the header grammar refuses fails the requests coalesced on it and is cached
  # for none of the later ones.
  class CoalescingTest < DexpaceTestCase
    include Fixtures

    test "AUTH-35 through the step: a refused token fails its waiters; the next one refetches" do
      provider = ScriptedBearerProvider.new("abc\n", "clean") # once refused, then clean forever
      step = async_step(stamper: async_bearer_over(provider))
      transport = settled(ok, ok)
      pipeline = async_auth_pipeline(step, transport)
      first = pipeline.call(https_request)

      assert_predicate(first, :settled?)
      assert_raises(Dexpace::Auth::ProviderError) { first.value }
      assert_empty(transport.calls) # the token could never be sent, and was not
      second = pipeline.call(https_request)
      third = pipeline.call(https_request)

      assert_equal([200, 200], [second.value.status.code, third.value.status.code])
      assert_equal(["Bearer clean", "Bearer clean"], transport.authorization_headers)
      assert_equal(2, provider.fetches) # refetched once, then served from the cache
    end

    test "AUTH-37, SEAM-18: cancelling one request's future leaves the coalesced others driving" do
      completer = Completer.new
      provider = ScriptedAsyncBearerProvider.new(completer.future)
      step = async_step(stamper: async_bearer_over(provider))
      transport = settled(ok, ok)
      pipeline = async_auth_pipeline(step, transport)
      first = pipeline.call(https_request)
      second = pipeline.call(https_request)
      first.cancel(:caller_gave_up)

      assert_predicate(first, :cancelled?)
      refute_predicate(second, :settled?)
      refute_predicate(completer.future, :settled?)
      assert_empty(transport.calls)
      third = pipeline.call(https_request) # arrives during the fetch, after the cancellation

      assert_equal(1, provider.fetches)
      completer.fulfil(Dexpace::Auth::BearerToken.build(token: "fresh"))

      assert_equal(200, second.value.status.code)
      assert_equal(200, third.value.status.code)
      assert_equal(["Bearer fresh", "Bearer fresh"], transport.authorization_headers)
      assert_equal(:caller_gave_up, assert_raises(Dexpace::CancelledError) { first.value }.reason)
    end
  end
end
