# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/step"
require_relative "../../../lib/dexpace/auth/async_step"
require_relative "../../../lib/dexpace/auth/key_stamper"
require_relative "../../../lib/dexpace/auth/key_credential"
require_relative "../../../lib/dexpace/auth/basic_handler"
require_relative "../../../lib/dexpace/auth/digest_handler"
require_relative "../../../lib/dexpace/auth/challenge_handler_chain"
require_relative "../../support/auth_fixtures"
require_relative "../../support/state_probe"
require_relative "../../support/fixed_cnonce"

# Exercises: AUTH-27, AUTH-28, AUTH-29 (both branches), AUTH-30 through AUTH-33, AUTH-31's
# uniformity -- one shared example set run against BOTH runtimes through real pipelines with
# phase 4c's ForkingProbe standing in for the REDIRECT step and StateProbe reading the slots,
# so the two steps are proven to agree rather than tested twice by hand. The set is first run
# against a deliberately broken step to show it is not vacuously green. No lib/ mirror: a
# cross-cutting suite over step.rb and async_step.rb.
class DexpaceAuthPillarIntegrationTest < DexpaceTestCase
  STAGES = Dexpace::Pipeline::Stages

  # One runtime: how to build a pipeline, which transport it takes, and how a result is read.
  Runtime = Struct.new(:name, :step_class, :transport_class, :build, :resolve) do
    def pipeline(steps, transport)
      builder = Dexpace::Pipeline::Builder.new(transport: transport)
      steps.each do |step, stage|
        stage.nil? ? builder.append(step) : builder.append(step, stage: stage)
      end
      build.call(builder)
    end
  end

  SYNC = Runtime.new("sync", Dexpace::Auth::Step, SequencedTransport, :build.to_proc,
                     :itself.to_proc,)
  ASYNC = Runtime.new("async", Dexpace::Auth::AsyncStep, SequencedAsyncTransport,
                      :build_async.to_proc, :value.to_proc,)

  # A step of the right stage whose every branch is wrong: stamps cross-origin, skips the
  # guard, never replays. The shared examples must fail against it.
  class BrokenStep
    def initialize(stamper) = @stamper = stamper
    def stage = Dexpace::Pipeline::Stages::AUTH
    def call(request, cursor) = cursor.fork.call(@stamper.call(request))

    # The .build shape the examples construct through; the hook is what a broken step ignores.
    def self.build(stamper:, **) = new(stamper)
  end

  # The helpers the example set is written over: a runtime-parametrised dispatch.
  module Harness
    include AuthFixtures

    def key_stamper
      Dexpace::Auth::KeyStamper.new(Dexpace::Auth::KeyCredential.new(api_key: "secret"))
    end

    def build_step(hook: Dexpace::Auth::Step::NO_REPLACEMENT)
      runtime.step_class.build(stamper: key_stamper, challenge_hook: hook)
    end

    def redirect_probe(state) = ForkingProbe.new(times: 1, state_per_drive: [state])

    def redirected(state, *rest) = [[redirect_probe(state), STAGES::REDIRECT], *rest]

    def transport(*script) = runtime.transport_class.new(*script)

    def dispatch(steps, transport, request = https_request)
      runtime.resolve.call(runtime.pipeline(steps, transport).call(request))
    end

    def failure_of(steps, transport, request)
      dispatch(steps, transport, request)
      nil
    rescue StandardError => error
      error
    end

    def echo_hook = ->(_c, request, _r) { request }
  end

  # The shared examples, written once, parametrised by the runtime: the stamping half.
  module StampExamples
    include Harness

    def examples_cross_origin_suppresses_stamp_and_guard
      wire = transport(ok)
      reader = StateProbe.new(stage_to_read: STAGES::REDIRECT)
      steps = redirected({ cross_origin: true }, [build_step, nil], [reader, STAGES::POST_AUTH])
      response = dispatch(steps, wire, http_request)

      assert_equal(200, response.status.code)
      assert_equal([nil], wire.authorization_headers)
      assert_equal([{ cross_origin: true }], reader.reads)
    end

    def examples_same_origin_restamps_and_reguards
      wire = transport(ok)
      dispatch(redirected({ cross_origin: false }, [build_step, nil]), wire)

      assert_equal(["secret"], wire.authorization_headers)
      error = failure_of(redirected({ cross_origin: false }, [build_step, nil]), transport(ok),
                         http_request,)

      assert_kind_of(Dexpace::Auth::HTTPSRequiredError, error)
    end

    def examples_no_redirect_step_stamps
      wire = transport(ok)
      dispatch([[build_step, nil]], wire)

      assert_equal(["secret"], wire.authorization_headers)
    end

    def examples_guard_before_stamp
      wire = transport(ok)
      error = failure_of([[build_step, nil]], wire, http_request)

      assert_kind_of(Dexpace::Auth::HTTPSRequiredError, error)
      assert_equal(runtime.step_class.name, error.step)
      assert_empty(wire.calls)
    end

    def examples_stage_order_redirect_wraps_auth
      order = []
      wire = transport(unauthorized("Basic realm=r"), ok)
      recorder = lambda do |request, cursor|
        order << :pre_auth
        cursor.call(request)
      end
      hook = lambda do |_c, request, _r|
        order << :hook
        request
      end
      steps = redirected({ cross_origin: false }, [recorder, STAGES::PRE_AUTH],
                         [build_step(hook: hook), nil],)
      dispatch(steps, wire)

      assert_equal(%i[pre_auth hook], order) # PRE_AUTH ran before AUTH replayed
      assert_equal(2, wire.calls.size)
    end
  end

  # The shared examples, the challenge half.
  module ChallengeExamples
    include Harness

    MUFASA_CHALLENGE = 'Digest realm="testrealm@host.com", qop="auth,auth-int", ' \
                       'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093"'

    def examples_replay_once_and_close
      first = unauthorized("Basic realm=r")
      wire = transport(first, unauthorized("Basic realm=r"), ok)
      response = dispatch([[build_step(hook: echo_hook), nil]], wire)

      assert_equal([401, 2], [response.status.code, wire.calls.size])
      assert_equal([1, 0], [closes_of(first), closes_of(response)])
    end

    def examples_unauthorized_without_challenge_passes_through
      consulted = false
      first = unauthorized(nil)
      hook = lambda do |*|
        consulted = true
        nil
      end
      response = dispatch([[build_step(hook: hook), nil]], transport(first, ok))

      assert_same(first, response)
      refute(consulted)
    end

    def examples_replay_gate_uniform
      first = unauthorized("Basic realm=r")
      wire = transport(first, ok)
      hook = ->(*) { post_request(replayable: false) }
      response = dispatch([[build_step(hook: hook), nil]], wire, post_request)

      assert_same(first, response)
      assert_equal(0, closes_of(first))
      assert_equal(1, wire.calls.size)
    end

    def examples_hook_error_closes_unauthorized
      first = unauthorized("Basic realm=r")
      hook = ->(*) { raise "boom" }
      error = failure_of([[build_step(hook: hook), nil]], transport(first, ok), https_request)

      assert_kind_of(RuntimeError, error)
      assert_equal(1, closes_of(first))
    end

    def examples_digest_end_to_end
      wire = transport(unauthorized(MUFASA_CHALLENGE), ok)
      response = dispatch([[digest_step, nil]], wire, mufasa_request)

      assert_equal(200, response.status.code)
      assert_nil(wire.authorization_headers.first)
      assert_includes(wire.authorization_headers.last,
                      'response="6629fae49393a05397450978507c4ef1"',)
    end

    def digest_step
      chain = Dexpace::Auth::ChallengeHandlerChain.new([mufasa_digest])
      runtime.step_class.build(stamper: Dexpace::Auth::Step::NO_STAMP,
                               challenge_hook: chain.as_challenge_hook,)
    end

    def examples_basic_preemptive
      credential = Dexpace::Auth::PasswordCredential.build(username: "alice", password: "s3cr3t")
      step = runtime.step_class.build(stamper: Dexpace::Auth::BasicHandler.new(credential))
      wire = transport(ok)
      dispatch([[step, nil]], wire)

      assert_equal(["Basic YWxpY2U6czNjcjN0"], wire.authorization_headers)
    end

    def mufasa_digest
      credential = Dexpace::Auth::PasswordCredential.build(username: "Mufasa",
                                                           password: "Circle Of Life",)
      Dexpace::Auth::DigestHandler.new(credential, cnonce_source: FixedCnonce.new("0a4f113b"))
    end

    def mufasa_request
      Dexpace::Request.build(method: "GET", url: "https://host/dir/index.html",
                             headers: Dexpace::Headers::EMPTY,)
    end
  end

  # Both halves, and the one place the example list is taken from.
  module Examples
    include StampExamples
    include ChallengeExamples
  end

  EXAMPLE_NAMES = [StampExamples, ChallengeExamples].flat_map do |half|
    half.instance_methods(false)
  end
    .grep(/\Aexamples_/).sort

  # The examples against the sync step.
  class SyncTest < DexpaceTestCase
    include Examples

    def runtime = SYNC

    EXAMPLE_NAMES.each do |example|
      test "sync: #{example.to_s.delete_prefix("examples_").tr("_", " ")}" do
        send(example)
      end
    end
  end

  # The examples against the async step.
  class AsyncTest < DexpaceTestCase
    include Examples

    def runtime = ASYNC

    EXAMPLE_NAMES.each do |example|
      test "async: #{example.to_s.delete_prefix("examples_").tr("_", " ")}" do
        send(example)
      end
    end
  end

  # The sanity check: the examples are not vacuously green.
  class BrokenTest < DexpaceTestCase
    include Examples

    def runtime
      Runtime.new("broken", BrokenStep, SequencedTransport, :build.to_proc, :itself.to_proc)
    end

    test "the shared examples fail against a deliberately broken step" do
      failed = EXAMPLE_NAMES.count do |example|
        send(example)
        false
      rescue Minitest::Assertion, StandardError
        true
      end

      assert_operator(failed, :>=, 7,
                      "only #{failed} of #{EXAMPLE_NAMES.size} examples caught the broken step",)
    end
  end
end
