# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/step"
require_relative "../../../lib/dexpace/auth/bearer_stamper"
require_relative "../../support/auth_fixtures"
require_relative "../../support/scripted_bearer_provider"
require_relative "../../support/spy_cursor"
require_relative "../../support/fake_clock"

# Exercises: AUTH-36 (the step half), AUTH-31 (P6-7) -- the sync step's bearer 401 branch: a
# Bearer challenge evicts exactly the rejected token and re-stamps ONE retry with a fresh
# fetch, regardless of method; a token another request refreshed is preserved and reused; no
# Authorization on the rejected request, or no Bearer challenge, surfaces the 401 unchanged; a
# non-replayable body skips the retry and leaves the 401 unclosed; the branch runs before the
# challenge hook; a provider token the header grammar refuses fails one dispatch and no later
# one (review round 3's R3-1). No lib/ mirror: a second suite over step.rb, like 5b's
# downstream_wirings. Split under Metrics/ClassLength.
class DexpaceAuthStepBearerChallengeTest < DexpaceTestCase
  Step = Dexpace::Auth::Step
  STAGES = Dexpace::Pipeline::Stages

  # The bearer steps and dispatch the two cases share.
  module Fixtures
    include AuthFixtures

    def provider(*tokens) = ScriptedBearerProvider.new(*tokens)

    def bearer_stamper(prov)
      Dexpace::Auth::BearerStamper.new(provider: prov, clock: FakeClock.new)
    end

    def bearer_step(prov, hook: Step::NO_REPLACEMENT)
      Step.build(stamper: bearer_stamper(prov), challenge_hook: hook)
    end

    def dispatch(step, transport, request = https_request, redirect_state: nil)
      auth_pipeline(step, transport, redirect_state: redirect_state).call(request)
    end
  end

  # The retry itself: eviction, one fresh fetch, any method, one fork.
  class RetryTest < DexpaceTestCase
    include Fixtures

    test "AUTH-36: a 401 with a Bearer challenge evicts the token and retries once, freshly" do
      prov = provider("old", "new")
      first = unauthorized_bearer
      closed_at_retry = nil
      retry_reply = lambda do |_request|
        closed_at_retry = closes_of(first) # read AS the retry reaches the transport (R1-2)
        ok
      end
      transport = SequencedTransport.new(first, retry_reply)
      response = dispatch(bearer_step(prov), transport)

      assert_equal(200, response.status.code)
      assert_equal(["Bearer old", "Bearer new"], transport.authorization_headers)
      assert_equal(2, prov.fetches)
      assert_equal(1, closed_at_retry) # the superseded 401 is closed BEFORE the retry drives
      assert_equal(0, closes_of(response))
    end

    test "AUTH-36: the retry fires regardless of HTTP method -- a POST is retried too" do
      transport = SequencedTransport.new(unauthorized_bearer, ok)
      response = dispatch(bearer_step(provider("old", "new")), transport, post_request)

      assert_equal(200, response.status.code)
      assert_equal(["Bearer old", "Bearer new"], transport.authorization_headers)
      assert_equal(%w[POST POST], transport.requests.map { |request| request.method.to_s })
    end

    test "AUTH-36: a token another request already refreshed is preserved and reused" do
      prov = provider("old", "never-fetched")
      stamper = bearer_stamper(prov)
      refreshed = Dexpace::Auth::BearerToken.build(token: "refreshed-elsewhere")
      # The first drive is stamped from the cache ("old", fetched once); the transport swaps the
      # cache before answering 401, standing in for the other request's refresh.
      swap = lambda do |_request|
        stamper.instance_variable_set(:@token, refreshed)
        unauthorized_bearer
      end
      transport = SequencedTransport.new(swap, ok)
      dispatch(Step.build(stamper: stamper), transport)

      assert_equal(["Bearer old", "Bearer refreshed-elsewhere"], transport.authorization_headers)
      assert_equal(1, prov.fetches)
    end

    test "AUTH-36: the retry drives a fresh fork exactly once and never the handed cursor" do
      spy = nil
      step = bearer_step(provider("old", "new"))
      wrapper = ->(request, cursor) { step.call(request, spy = SpyCursor.new(cursor)) }
      transport = SequencedTransport.new(unauthorized_bearer, unauthorized_bearer, ok)
      response = Dexpace::Pipeline.builder(transport: transport)
        .append(wrapper, stage: STAGES::AUTH)
        .build.call(https_request)

      assert_equal(401, response.status.code) # ONE retry only: the second 401 surfaces
      assert_equal(2, spy.forks)
      assert_equal(0, spy.calls)
      assert_equal(2, transport.calls.size)
    end

    test "AUTH-35 on the retry: a provider raising during the re-stamp propagates, 401 closed" do
      first = unauthorized_bearer
      transport = SequencedTransport.new(first, ok)
      step = bearer_step(provider("old", RuntimeError.new("boom")))

      assert_raises(RuntimeError) { dispatch(step, transport) }
      assert_equal(1, closes_of(first))
    end

    test "AUTH-35 through the step: a refused token fails one dispatch; the next fetches again" do
      transport = SequencedTransport.new(ok, ok)
      prov = provider("abc\n", "clean") # once refused, then clean forever
      step = bearer_step(prov)

      assert_raises(Dexpace::Auth::ProviderError) { dispatch(step, transport) }
      assert_empty(transport.calls) # the token could never be sent, and was not
      assert_equal(200, dispatch(step, transport).status.code)
      assert_equal(200, dispatch(step, transport).status.code)
      assert_equal(["Bearer clean", "Bearer clean"], transport.authorization_headers)
      assert_equal(2, prov.fetches) # refetched once, then served from the cache
    end
  end

  # The four ways the branch surfaces the 401 unchanged, and its place before the hook.
  class SurfaceTest < DexpaceTestCase
    include Fixtures

    test "AUTH-36: no Authorization on the rejected request (cross-origin) surfaces the 401" do
      prov = provider("old")
      first = unauthorized_bearer
      transport = SequencedTransport.new(first, ok)
      response = dispatch(bearer_step(prov), transport, redirect_state: { cross_origin: true })

      assert_same(first, response)
      assert_equal(1, transport.calls.size)
      assert_equal([nil], transport.authorization_headers)
      assert_equal(0, prov.fetches)
      assert_equal(0, closes_of(first))
    end

    test "AUTH-36: a 401 advertising no Bearer challenge surfaces unchanged, no eviction" do
      prov = provider("old")
      first = unauthorized('Basic realm="r"')
      transport = SequencedTransport.new(first, ok)
      step = bearer_step(prov)
      response = dispatch(step, transport)

      assert_same(first, response)
      assert_equal(1, transport.calls.size)
      assert_equal(1, prov.fetches)
      assert_equal(0, closes_of(first))
      # Still cached: a second dispatch stamps without fetching.
      dispatch(step, SequencedTransport.new(ok))

      assert_equal(1, prov.fetches)
    end

    test "AUTH-31, P6-7: a non-replayable body skips the bearer retry; the 401 is left UNCLOSED" do
      prov = provider("old", "new")
      first = unauthorized_bearer
      transport = SequencedTransport.new(first, ok)
      response = dispatch(bearer_step(prov), transport, post_request(replayable: false))

      assert_same(first, response)
      assert_equal(0, closes_of(first))
      assert_equal(1, transport.calls.size)
      assert_equal(1, prov.fetches) # nothing evicted, nothing re-fetched
    end

    test "AUTH-30: the bearer branch is not the challenge hook, which is never consulted for it" do
      consulted = false
      hook = lambda do |*|
        consulted = true
        nil
      end
      transport = SequencedTransport.new(unauthorized_bearer, ok)
      response = dispatch(bearer_step(provider("old", "new"), hook: hook), transport)

      assert_equal(200, response.status.code)
      refute(consulted)
    end

    test "AUTH-30: the hook IS consulted for a bearer stamper when the challenge is not Bearer" do
      consulted = false
      hook = lambda do |*|
        consulted = true
        nil
      end
      transport = SequencedTransport.new(unauthorized('Digest realm="r", nonce="n"'), ok)
      dispatch(bearer_step(provider("old"), hook: hook), transport)

      assert(consulted)
    end
  end
end
