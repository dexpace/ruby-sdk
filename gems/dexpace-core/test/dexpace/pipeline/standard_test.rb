# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/redirect_fixtures"
require_relative "../../support/fake_async_transport"
require_relative "../../support/fake_clock"
require_relative "../../support/recording_sink"
require_relative "../../support/recording_http_tracer"
require_relative "../../support/scripted_async_transport"

# Exercises: PIPE-39 (the second convenience constructor), PIPE-24 (consumed), PIPE-32 and
# REDIR-25 (no longer vacuous) -- Pipeline.standard and AsyncPipeline.standard, the two
# constructors phase 4c postponed to phase 6 and phase 6b's Task 13a wrote OVER
# Builder#install_preset: the sync preset is redirect + retry + instrumentation, the async
# preset retry + instrumentation with `redirect: :unsupported` REQUIRED at the call site, and
# neither has a second installation path. No lib/ mirror: pipeline.rb and async_pipeline.rb
# have theirs; this suite is the two constructors' own, over both files.
class DexpacePipelineStandardTest < DexpaceTestCase
  # The transports, settings and readers the nested cases share.
  module Fixtures
    include RedirectFixtures

    def sync_transport(*script) = ScriptedTransport.new(script)

    def async_transport = FakeAsyncTransport.new(response: response_with(200))

    def stage_names(pipeline) = pipeline.entries.map { |entry| entry.stage.name }

    # Flat, zero-delay settings over a recording clock; `overrides` reach RetrySettings.build.
    def settings(clock: FakeClock.new, **overrides)
      Dexpace::Resilience::RetrySettings.build(initial_delay: 0.0, jitter: 0.0, clock: clock,
                                               **overrides,)
    end

    def event_names(sink) = sink.payloads.map { |p| p[Dexpace::Instrumentation::Keys::EVENT] }

    def logger_over(sink) = Dexpace::Instrumentation::Logger.build(sink: sink)
  end

  # The shapes: what each preset installs, and PIPE-32's required keyword.
  class ShapeTest < DexpaceTestCase
    include Fixtures

    test "PIPE-39: the sync standard pipeline installs redirect, retry and logging, nothing else" do
      pipeline = Dexpace::Pipeline.standard(sync_transport)

      assert_equal(%i[redirect retry logging], stage_names(pipeline))
      assert_instance_of(Dexpace::Redirect::Step, pipeline.entries[0].step)
      assert_instance_of(Dexpace::Resilience::RetryStep, pipeline.entries[1].step)
      assert_instance_of(Dexpace::Instrumentation::Step, pipeline.entries[2].step)
      assert_instance_of(Dexpace::Pipeline, pipeline)
    end

    test "PIPE-32 / REDIR-25: the async standard pipeline installs NO step at Stages::REDIRECT" do
      pipeline = Dexpace::AsyncPipeline.standard(async_transport, redirect: :unsupported)

      assert_equal(%i[retry logging], stage_names(pipeline))
      assert_instance_of(Dexpace::Resilience::AsyncRetryStep, pipeline.entries[0].step)
      assert_instance_of(Dexpace::Instrumentation::AsyncStep, pipeline.entries[1].step)
      assert_instance_of(Dexpace::AsyncPipeline, pipeline)
    end

    test "PIPE-32: the async constructor REQUIRES redirect: and accepts only :unsupported" do
      assert_raises(ArgumentError) { Dexpace::AsyncPipeline.standard(async_transport) }
      [:follow, nil, true, Dexpace::Redirect::Step.build].each do |value|
        error = assert_raises(Dexpace::InvalidArgumentError) do
          Dexpace::AsyncPipeline.standard(async_transport, redirect: value)
        end

        assert_includes(error.message, "PIPE-32")
      end
    end
  end

  # PIPE-24 through the constructors, and the one installation path.
  class InstallationTest < DexpaceTestCase
    include Fixtures

    test "PIPE-24: both constructors go through Builder#install_preset -- an occupied pillar in " \
         "the builder handed in rejects the whole preset, installing nothing" do
      occupant = Dexpace::Resilience::RetryStep.build
      builder = Dexpace::Pipeline.builder(transport: sync_transport).append(occupant)
      error = assert_raises(Dexpace::PipelineError) { Dexpace::Pipeline.standard(builder) }

      assert_includes(error.message, "PIPE-24")
      assert_equal([occupant], builder.entries.map(&:step))

      async_builder = Dexpace::Pipeline::Builder.new(transport: async_transport)
      async_builder.append(Dexpace::Resilience::AsyncRetryStep.build)
      assert_raises(Dexpace::PipelineError) do
        Dexpace::AsyncPipeline.standard(async_builder, redirect: :unsupported)
      end

      assert_equal(1, async_builder.entries.size)
    end

    test "PIPE-24 / PIPE-39: a builder handed in keeps its own steps around the preset's" do
      marker = ->(request, cursor) { cursor.call(request) }
      builder = Dexpace::Pipeline.builder(transport: sync_transport(response_with(200)))
      builder.append(marker, stage: STAGES::PRE_REDIRECT)
      pipeline = Dexpace::Pipeline.standard(builder)

      assert_equal(%i[pre_redirect redirect retry logging], stage_names(pipeline))
      assert_equal(200, pipeline.call(seed_request).status.code)
    end

    test "no second installation path: both constructors are written over install_preset alone" do
      %w[pipeline.rb async_pipeline.rb].each do |file|
        source = File.read(File.expand_path("../../../lib/dexpace/#{file}", __dir__))
        body = source[/def self\.standard.*?^    end$/m]

        refute_nil(body, file)
        assert_includes(body, "install_preset", file)
        refute_match(/\.(append|prepend|insert_after|insert_before|replace|reload)\b/, body, file)
      end
    end
  end

  # The keywords reaching the steps, on both presets.
  class WiringTest < DexpaceTestCase
    include Fixtures

    test "PIPE-39: settings: and http_tracer_factory: reach the retry step, logger: and level: " \
         "the instrumentation step, on the sync preset" do
      tracer = Dexpace::RecordingHTTPTracer.new
      sink = RecordingSink.new
      clock = FakeClock.new
      transport = sync_transport(response_with(503), response_with(200))
      pipeline = Dexpace::Pipeline.standard(
        transport, settings: settings(clock: clock), http_tracer_factory: ->(_cursor) { tracer },
                   logger: logger_over(sink), level: Dexpace::Instrumentation::HTTPLogging::HEADERS,
      )

      assert_equal(200, pipeline.call(seed_request).status.code)
      assert_equal(2, transport.calls.size) # the 503 was retried under the flat settings
      # The retry's one wait ran on THESE settings' clock at their zero delay. The default
      # settings retry a 503 too -- after a real ~0.2 s backoff on Clock::SYSTEM that leaves this
      # clock empty -- so the call count alone cannot tell whether settings: reached the step.
      assert_equal([0.0], clock.sleeps.map { |sleep| sleep[:duration] })
      assert_equal(%i[attempt_started attempt_failed attempt_started], tracer.events.map(&:first))
      requests = event_names(sink).count(Dexpace::Instrumentation::Events::HTTP_REQUEST)

      assert_equal(2, requests) # one per attempt: the instrumentation step sits inside RETRY
    end

    test "PIPE-39: settings: alone governs the sync retry step -- max_retries: 0 leaves a 503 " \
         "unretried where the default schedule would have retried it" do
      transport = sync_transport(response_with(503))
      pipeline = Dexpace::Pipeline.standard(transport, settings: settings(max_retries: 0))

      assert_equal(503, pipeline.call(seed_request).status.code)
      assert_equal(1, transport.calls.size)
    end

    test "PIPE-39: the sync preset follows a redirect and retries a 503 in one call, and the " \
         "redirect step is built over the preset's logger" do
      sink = RecordingSink.new
      transport = sync_transport(response_with(503),
                                 response_with(302, location: "https://a.example/y"),
                                 response_with(200),)
      pipeline = Dexpace::Pipeline.standard(transport, settings: settings,
                                                       logger: logger_over(sink),)

      assert_equal(200, pipeline.call(seed_request).status.code)
      assert_equal(%w[https://a.example/x https://a.example/x https://a.example/y],
                   sent_urls(transport),)
      assert_includes(event_names(sink), Dexpace::Redirect::Events::HOP_FOLLOWED)
    end

    test "PIPE-39: a redirect: step handed in is installed as given" do
      step = Dexpace::Redirect::Step.build(max_hops: 0)
      transport = sync_transport(response_with(302, location: "https://a.example/y"))
      pipeline = Dexpace::Pipeline.standard(transport, redirect: step)

      assert_same(step, pipeline.entries[0].step)
      assert_equal(302, pipeline.call(seed_request).status.code)
    end

    test "PIPE-39: settings:, http_tracer_factory:, logger: and level: reach the async steps" do
      tracer = Dexpace::RecordingHTTPTracer.new
      sink = RecordingSink.new
      transport = ScriptedAsyncTransport.new([response_with(503), response_with(200)])
      pipeline = Dexpace::AsyncPipeline.standard(
        transport, redirect: :unsupported, settings: settings,
                   http_tracer_factory: ->(_cursor) { tracer }, logger: logger_over(sink),
                   level: Dexpace::Instrumentation::HTTPLogging::HEADERS,
      )
      response = pipeline.call(seed_request).value

      assert_equal(200, response.status.code)
      assert_equal(%i[attempt_started attempt_failed attempt_started], tracer.events.map(&:first))
      refute_empty(sink.payloads)
    end

    test "PIPE-39: level: BODY needs preview_bytes:, threaded through both presets" do
      body = Dexpace::Instrumentation::HTTPLogging::BODY
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Pipeline.standard(sync_transport, level: body) }

      pipeline = Dexpace::Pipeline.standard(sync_transport, level: body, preview_bytes: 64)

      assert_equal(%i[redirect retry logging], stage_names(pipeline))
      async = Dexpace::AsyncPipeline.standard(async_transport, redirect: :unsupported, level: body,
                                                               preview_bytes: 64,)

      assert_equal(%i[retry logging], stage_names(async))
    end

    test "PIPE-39: the sync constructor refuses a non-transport and a foreign redirect: value" do
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Pipeline.standard(Object.new) }
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Pipeline.standard(sync_transport, redirect: :unsupported)
      end
    end
  end
end
