# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/step"
require_relative "../../../lib/dexpace/auth/key_stamper"
require_relative "../../../lib/dexpace/auth/key_credential"
require_relative "../../support/auth_fixtures"
require_relative "../../support/spy_cursor"
require_relative "../../support/fake_transport"

# Exercises: AUTH-27 through AUTH-33 -- the sync AUTH pillar step, driven through a real
# pipeline (only the driver makes a forkable cursor): the stage, the HTTPS guard before any
# stamp, AUTH-29's three cases read from Stages::REDIRECT's slot, forking for every drive and
# never calling the handed cursor, the 401 re-challenge replay, its default, its replayability
# gate, the close-on-hook-error, and the no-challenge pass-through. Split under
# Metrics/ClassLength.
class DexpaceAuthStepTest < DexpaceTestCase
  Step = Dexpace::Auth::Step
  STAGES = Dexpace::Pipeline::Stages

  # The steps, requests and pipelines the nested cases share.
  module Fixtures
    include AuthFixtures

    def key_stamper(key = "secret")
      Dexpace::Auth::KeyStamper.new(Dexpace::Auth::KeyCredential.new(api_key: key))
    end

    def step(stamper: key_stamper, hook: Step::NO_REPLACEMENT)
      Step.build(stamper: stamper, challenge_hook: hook)
    end

    def transport_of(response) = FakeTransport.new(response: response)

    # The step behind a recording wrapper, so the cursor it is handed can be inspected.
    def spied(auth_step)
      spy = nil
      wrapper = lambda do |request, cursor|
        spy = SpyCursor.new(cursor)
        auth_step.call(request, spy)
      end
      [wrapper, -> { spy }]
    end

    def dispatch(auth_step, transport, request = https_request, redirect_state: nil, stage: nil)
      builder = Dexpace::Pipeline.builder(transport: transport)
      unless redirect_state.nil?
        builder.append(ForkingProbe.new(times: 1, state_per_drive: [redirect_state]),
                       stage: STAGES::REDIRECT,)
      end
      stage.nil? ? builder.append(auth_step) : builder.append(auth_step, stage: stage)
      builder.build.call(request)
    end

    def stamped_on(transport) = transport.calls.first.first.headers["Authorization"]
  end

  # AUTH-27, the construction pattern and the two default callables.
  class ConstructionTest < DexpaceTestCase
    include Fixtures

    test "AUTH-27: declares Stages::AUTH, the one pillar stage, and installs without a stage:" do
      auth_step = step

      assert_same(STAGES::AUTH, auth_step.stage)
      pipeline = Dexpace::Pipeline.builder(transport: transport_of(ok)).append(auth_step).build

      assert_equal([STAGES::AUTH], pipeline.entries.map(&:stage))
      assert_raises(Dexpace::PipelineError) do
        Dexpace::Pipeline.builder(transport: transport_of(ok)).append(auth_step).append(step).build
      end
    end

    test "5b's shape: .build with .new private, frozen, the stamper and hook validated by arity" do
      refute_respond_to(Step, :new)
      assert_predicate(step, :frozen?)
      assert_raises(Dexpace::InvalidArgumentError) { Step.build(stamper: Object.new) }
      assert_raises(Dexpace::InvalidArgumentError) { Step.build(stamper: ->(_a, _b) {}) }
      assert_raises(Dexpace::InvalidArgumentError) { step(hook: ->(_a) {}) }
      assert_raises(Dexpace::InvalidArgumentError) { Step.build(stamper: key_stamper, logger: nil) }
    end

    test "AUTH-30, AUTH-1: the two defaults -- no replacement, and the identity stamper" do
      request = https_request

      assert_nil(Step::NO_REPLACEMENT.call("Basic realm=r", request, unauthorized))
      assert_same(request, Step::NO_STAMP.call(request))
    end
  end

  # AUTH-28: the HTTPS guard, before any stamp.
  class GuardTest < DexpaceTestCase
    include Fixtures

    test "AUTH-28: a plaintext URL is refused BEFORE any stamp, naming the step and the scheme" do
      stamped = false
      transport = transport_of(ok)
      stamper = lambda do |request|
        stamped = true
        request
      end
      error = assert_raises(Dexpace::Auth::HTTPSRequiredError) do
        dispatch(step(stamper: stamper), transport, http_request)
      end

      assert_equal("http", error.scheme)
      assert_equal("Dexpace::Auth::Step", error.step)
      refute(stamped)
      assert_empty(transport.calls)
    end

    test "AUTH-28: the scheme comparison is case-insensitive; the guard also covers NO_STAMP" do
      upper = Dexpace::Request.build(method: "GET", url: "HTTPS://api.example.test/",
                                     headers: Dexpace::Headers::EMPTY,)
      transport = transport_of(ok)

      assert_equal(200, dispatch(step, transport, upper).status.code)
      assert_raises(Dexpace::Auth::HTTPSRequiredError) do
        dispatch(step(stamper: Step::NO_STAMP), transport, http_request)
      end
    end

    test "AUTH-28 with a bare Cursor.build: the guard fires before the stamper on the root too" do
      cursor = Dexpace::Pipeline::Cursor.build(drive: Object.new, request: http_request,
                                               options: Dexpace::RequestOptions::EMPTY,
                                               cancellation: Dexpace::Cancellation.none,)
      stamper = ->(_request) { flunk "must not stamp before the guard" }

      assert_raises(Dexpace::Auth::HTTPSRequiredError) do
        step(stamper: stamper).call(http_request, cursor)
      end
    end
  end

  # AUTH-29: the marker read from the redirect step's slot, and only from there.
  class CrossOriginTest < DexpaceTestCase
    include Fixtures

    test "AUTH-29: a cross-origin re-issue is neither guarded nor stamped, and still forks" do
      transport = transport_of(ok)
      wrapper, spy = spied(step(stamper: ->(_request) { flunk "must not stamp cross-origin" }))
      response = dispatch(wrapper, transport, http_request, redirect_state: { cross_origin: true },
                                                            stage: STAGES::AUTH,)

      assert_equal(200, response.status.code)
      assert_nil(stamped_on(transport))
      assert_equal(1, spy.call.forks)
      assert_equal(0, spy.call.calls)
      refute_predicate(spy.call.cursor, :spent?)
    end

    test "AUTH-29: a same-origin re-issue (cross_origin: false) is re-stamped and re-guarded" do
      transport = transport_of(ok)
      dispatch(step, transport, redirect_state: { cross_origin: false })

      assert_equal(["secret"], stamped_on(transport))
      assert_raises(Dexpace::Auth::HTTPSRequiredError) do
        dispatch(step, transport, http_request, redirect_state: { cross_origin: false })
      end
    end

    test "AUTH-29: no REDIRECT step at all -- the shared frozen empty slot -- is same-origin" do
      transport = transport_of(ok)
      dispatch(step, transport)

      assert_equal(["secret"], stamped_on(transport))
    end

    test "AUTH-29: the marker is read from the cursor and never from a request header" do
      transport = transport_of(ok)
      forged = https_request(headers: Dexpace::Headers.builder
        .add("X-Dexpace-Cross-Origin", "true").build)
      dispatch(step, transport, forged)

      assert_equal(["secret"], stamped_on(transport))
    end

    test "AUTH-29 / 4c's assertion 4: a RETRY step's slot cannot suppress the AUTH stamp" do
      transport = transport_of(ok)
      retry_probe = ForkingProbe.new(times: 1, state_per_drive: [{ cross_origin: true }])
      Dexpace::Pipeline.builder(transport: transport)
        .append(retry_probe, stage: STAGES::RETRY)
        .append(step)
        .build.call(https_request)

      assert_equal(["secret"], stamped_on(transport))
    end

    # 4c's negative assertion 4 from the AUTH side: a fork from the AUTH step's own cursor
    # writes the AUTH slot and cannot reach REDIRECT's, and the cursor has no setter at all.
    test "AUTH-29: an AUTH-stage fork cannot write REDIRECT's slot; no cursor method sets state" do
      seen = nil
      reader = lambda do |request, cursor|
        seen = cursor.state(STAGES::REDIRECT)
        cursor.call(request)
      end
      forger = ->(request, cursor) { cursor.fork(state: { cross_origin: false }).call(request) }
      redirect_probe = ForkingProbe.new(times: 1, state_per_drive: [{ cross_origin: true }])
      Dexpace::Pipeline.builder(transport: transport_of(ok))
        .append(redirect_probe, stage: STAGES::REDIRECT)
        .append(forger, stage: STAGES::AUTH)
        .append(reader, stage: STAGES::POST_AUTH)
        .build.call(https_request)

      assert_equal({ cross_origin: true }, seen)
      setters = Dexpace::Pipeline::Cursor.public_instance_methods(false).grep(/state=|write/)

      assert_empty(setters)
    end
  end

  # AUTH-30 and P4-39: the drive, the replay and the pass-throughs.
  class DriveTest < DexpaceTestCase
    include Fixtures

    test "P4-39: forks for every drive including the first; never calls the handed cursor" do
      transport = transport_of(ok)
      wrapper, spy = spied(step)
      dispatch(wrapper, transport, stage: STAGES::AUTH)

      assert_equal(1, spy.call.forks)
      assert_equal(0, spy.call.calls)
      assert_equal(1, transport.calls.size)
    end

    test "AUTH-30: non-401 responses pass through with the stamped request sent once" do
      transport = transport_of(closable_response(500))
      response = dispatch(step, transport)

      assert_equal(500, response.status.code)
      assert_equal(0, closes_of(response))
      assert_equal(1, transport.calls.size)
    end

    test "AUTH-30: a 401 with a challenge consults the hook and replays the replacement once" do
      seen = []
      replacement = https_request(headers: Dexpace::Headers.builder
        .add("Authorization", "Digest x").build)
      hook = lambda do |challenge, request, response|
        seen << [challenge, request, response]
        replacement
      end
      transport = SequencedTransport.new(unauthorized('Digest realm="r", nonce="n"'), ok)
      wrapper, spy = spied(step(hook: hook))
      response = dispatch(wrapper, transport, stage: STAGES::AUTH)

      assert_equal(200, response.status.code)
      assert_equal(['Digest realm="r", nonce="n"'], seen.map(&:first))
      assert_equal(["secret"], seen.first[1].headers["Authorization"]) # the stamped request
      assert_equal(401, seen.first[2].status.code)
      assert_equal(["secret", "Digest x"], transport.authorization_headers)
      assert_equal(2, spy.call.forks)
      assert_equal(0, spy.call.calls)
    end

    # "Close the original 401 AND drive the replacement", in that order: the close count is
    # read as the replay reaches the transport, not after the fact, so a replay that raises
    # cannot leave the 401 open (review round 1's R1-2 -- a close-after-drive mutation survived
    # the count-only form).
    test "AUTH-30: the original 401 is closed BEFORE the replay drives; the replay's is not" do
      first = unauthorized("Basic realm=r")
      closed_at_replay = nil
      replay = lambda do |_request|
        closed_at_replay = closes_of(first)
        ok
      end
      transport = SequencedTransport.new(first, replay)
      response = dispatch(step(hook: ->(_c, request, _r) { request }), transport)

      assert_equal(1, closed_at_replay)
      assert_equal(1, closes_of(first))
      assert_equal(0, closes_of(response))
    end

    test "AUTH-30: no further challenge handling on the replacement -- a second 401 surfaces" do
      transport = SequencedTransport.new(unauthorized("Basic realm=r"),
                                         unauthorized("Basic realm=r"), ok,)
      calls = 0
      hook = lambda do |_c, request, _r|
        calls += 1
        request
      end
      response = dispatch(step(hook: hook), transport)

      assert_equal(401, response.status.code)
      assert_equal(1, calls)
      assert_equal(2, transport.calls.size)
    end

    test "AUTH-30: the default hook yields no replacement, so the 401 surfaces after one drive" do
      transport = SequencedTransport.new(unauthorized("Basic realm=r"), ok)
      response = dispatch(step, transport)

      assert_equal(401, response.status.code)
      assert_equal(1, transport.calls.size)
      assert_equal(0, closes_of(response))
    end

    test "AUTH-30, RFC 7235: a repeated WWW-Authenticate header reaches the hook as one list" do
      seen = nil
      hook = lambda do |challenge, _q, _r|
        seen = challenge
        nil
      end
      two = unauthorized(["Basic realm=r", 'Digest realm="r", nonce="n"'])
      transport = SequencedTransport.new(two, ok)
      dispatch(step(hook: hook), transport)

      assert_equal('Basic realm=r, Digest realm="r", nonce="n"', seen)
    end
  end

  # AUTH-31, AUTH-32, AUTH-33: the replay gate and the two pass-throughs.
  class ReplayGateTest < DexpaceTestCase
    include Fixtures

    test "AUTH-31: a non-replayable replacement body skips the replay; the 401 is left UNCLOSED" do
      first = unauthorized("Basic realm=r")
      transport = SequencedTransport.new(first, ok)
      hook = ->(_c, _q, _r) { post_request(replayable: false) }
      response = dispatch(step(hook: hook), transport, post_request)

      assert_same(first, response)
      assert_equal(0, closes_of(response))
      assert_equal(1, transport.calls.size)
    end

    test "AUTH-31: a replayable body, or no body, is replayed" do
      transport = SequencedTransport.new(unauthorized("Basic realm=r"), ok)
      hook = ->(_c, _q, _r) { post_request(replayable: true) }

      assert_equal(200, dispatch(step(hook: hook), transport, post_request).status.code)
      transport = SequencedTransport.new(unauthorized("Basic realm=r"), ok)
      response = dispatch(step(hook: ->(_c, request, _r) { request }), transport)

      assert_equal(200, response.status.code)
    end

    test "AUTH-32: a hook that raises leaves the open 401 closed, the error propagating as is" do
      first = unauthorized("Basic realm=r")
      transport = SequencedTransport.new(first, ok)
      error = assert_raises(RuntimeError) do
        dispatch(step(hook: ->(*) { raise "hook blew up" }), transport)
      end

      assert_equal("hook blew up", error.message)
      assert_equal(1, closes_of(first))
      assert_equal(1, transport.calls.size)
    end

    test "AUTH-32: a close failure while closing rides the hook error's suppressed trail" do
      first = closable_response(401, challenge: "Basic realm=r")
      first.body.instance_variable_set(:@close_error, IOError.new("close failed"))
      transport = SequencedTransport.new(first, ok)
      error = assert_raises(RuntimeError) do
        dispatch(step(hook: ->(*) { raise "hook blew up" }), transport)
      end

      assert_equal(["close failed"], Dexpace.suppressed(error).map(&:message))
    end

    test "AUTH-32: a hook returning something that is not a request closes the 401 and raises" do
      first = unauthorized("Basic realm=r")
      transport = SequencedTransport.new(first, ok)

      assert_raises(Dexpace::InvalidArgumentError) do
        dispatch(step(hook: ->(*) { "not a request" }), transport)
      end
      assert_equal(1, closes_of(first))
    end

    test "AUTH-33: a 401 without WWW-Authenticate is returned unchanged; the hook not consulted" do
      consulted = false
      first = unauthorized(nil)
      transport = SequencedTransport.new(first, ok)
      hook = lambda do |*|
        consulted = true
        nil
      end
      response = dispatch(step(hook: hook), transport)

      assert_same(first, response)
      refute(consulted)
      assert_equal(0, closes_of(response))
      assert_equal(1, transport.calls.size)
    end
  end
end
