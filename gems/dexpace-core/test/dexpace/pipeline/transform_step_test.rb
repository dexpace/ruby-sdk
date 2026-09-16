# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/forking_probe"
require_relative "../../support/recording_body"
require_relative "../../support/recovery_fixtures"

# PIPE-37, spec-forced boundaries 1 and 5, verified fact 12: the one generic adapter that installs
# a phase-4b Dexpace::Recovery::Transform into a non-pillar stage, and the only object in this
# phase that names a Dexpace::Recovery constant.
class DexpacePipelineTransformStepTest < DexpaceTestCase
  include RecoveryFixtures

  STAGES = Dexpace::Pipeline::Stages

  # A transform whose #call raises: the adapter passes only if it never touches #call (verified
  # fact 12), which is 4b's R8 clause 5 -- "so a future default on #call cannot change what the
  # pipeline does".
  class DummyTransform
    attr_reader :phase, :applied

    def initialize(phase)
      @phase = phase
      @applied = []
    end

    def apply(value)
      @applied << value
      "transformed_#{value}"
    end

    def call(_value)
      raise "must never be called (verified fact 12)"
    end
  end

  test ".build validates that the transform responds to #phase and #apply" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Pipeline::TransformStep.build(Object.new) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Pipeline::TransformStep.build(nil) }

    phase_only = Class.new { def phase = :request }.new

    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Pipeline::TransformStep.build(phase_only) }
  end

  # R8 clause 2's "neither may add a third phase", made mechanical on this side. The specific
  # mistake it catches: a phase naming the recovery-STEP list -- a recovery step is
  # Outcome -> Outcome and is not a transform at all, and no Outcome ever crosses into PIPE.
  test ".build validates that #phase is :request or :response, in SEAM-29's message form" do
    invalid = Class.new do
      def phase = :recovery
      def apply(value) = value
    end.new

    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Pipeline::TransformStep.build(invalid)
    end

    assert_includes(error.message, ":recovery")
  end

  test ".build exposes the transform and reads #phase once, at build" do
    changing = Class.new do
      attr_reader :reads

      def initialize = @reads = 0

      def phase
        @reads += 1
        :request
      end

      def apply(value) = value
    end.new
    step = Dexpace::Pipeline::TransformStep.build(changing)
    cursor = Class.new { def call(request) = request }.new

    assert_same(changing, step.transform)
    step.call("a", cursor)
    step.call("b", cursor)

    assert_equal(1, changing.reads, "#phase is read at build and never at call time")
    assert(Dexpace::Pipeline::Step.conforms?(step))
  end

  test "a :request transform applies before the drive, and calls #apply, never #call" do
    transform = DummyTransform.new(:request)
    step = Dexpace::Pipeline::TransformStep.build(transform)
    cursor = Class.new { def call(request) = "handled_#{request}" }.new

    assert_equal("handled_transformed_data", step.call("data", cursor))
    assert_equal(["data"], transform.applied)
  end

  # The guard that swaps the two branches fails both this test and the one above.
  test "a :response transform applies after the drive, and calls #apply, never #call" do
    transform = DummyTransform.new(:response)
    step = Dexpace::Pipeline::TransformStep.build(transform)
    cursor = Class.new { def call(request) = "handled_#{request}" }.new

    assert_equal("transformed_handled_data", step.call("data", cursor))
    assert_equal(["handled_data"], transform.applied)
  end

  # 4b's own transforms install as themselves through the adapter, with no subclass and no second
  # implementation (spec-forced boundary 1).
  test "phase 4b's three shipped transforms build into a step unchanged" do
    idempotency = Dexpace::Recovery::IdempotencyKeyStep.build(header: "Idempotency-Key",
                                                              strategy: ->(_req) { "k" },)
    identity = Dexpace::Recovery::ClientIdentityStep.build(header: "User-Agent", tokens: ["sdk/1"])
    mapping = Dexpace::Recovery::ErrorMappingStep.build

    [idempotency, identity, mapping].each do |transform|
      step = Dexpace::Pipeline::TransformStep.build(transform)

      assert_same(transform, step.transform)
    end
  end

  # One wrapper serves transforms whose correct placements differ -- PIPE-37 puts the error
  # mapping at PRE_REDIRECT; an idempotency key belongs at or before PRE_RETRY -- so the wrapper
  # declares no stage and the stage is named at install (R10).
  test "TransformStep declares no #stage, so the stage is named at install" do
    step = Dexpace::Pipeline::TransformStep.build(DummyTransform.new(:request))

    refute_respond_to(step, :stage)
    assert_raises(Dexpace::PipelineError) do
      Dexpace::Pipeline.builder(transport: ->(_r, _o, _c) {}).append(step)
    end
  end

  # PIPE-37 through the pipeline, where the two layers actually meet (spec-forced boundary 5).
  class PlacementTest < DexpaceTestCase
    include RecoveryFixtures

    # PIPE-37, asserted THROUGH the pipeline under a twice-forking REDIRECT: the PRE_REDIRECT slot
    # sees exactly one response, the terminal one, returned by identity with its body not read,
    # consumed or closed. Placement alone would not catch a wrapper that re-invoked the outer slot
    # per hop, or one that touched the body on the way past; this is the test that does. The
    # transform is 4b's real ErrorMappingStep, whose own suite proves the untouched pass at the
    # step level; this is the same clause proved at the pipeline level.
    test "PIPE-37: ErrorMappingStep at PRE_REDIRECT runs once and returns the 2xx untouched" do
      bodies = []
      responses = []
      transport = lambda do |request, _options, _cancellation|
        body = RecordingBody.new("payload")
        bodies << body
        response = build_response(200, body: body, request: request)
        responses << response
        response
      end
      mapping = Dexpace::Recovery::ErrorMappingStep.build
      step = Dexpace::Pipeline::TransformStep.build(mapping)
      applies = 0
      counting = lambda do |request, cursor|
        applies += 1
        step.call(request, cursor)
      end

      pipeline = Dexpace::Pipeline.builder(transport: transport)
        .append(counting, stage: STAGES::PRE_REDIRECT)
        .append(ForkingProbe.new(times: 2), stage: STAGES::REDIRECT)
        .build
      result = pipeline.call(build_request)

      assert_equal(2, responses.size, "the REDIRECT probe drove twice")
      assert_equal(1, applies, "PRE_REDIRECT ran exactly once, outside the redirect loop (PIPE-37)")
      assert_same(responses.last, result, "the terminal response, by identity")
      assert_equal(0, bodies.last.source_count, "body not read (PIPE-37)")
      assert_equal(0, bodies.last.release_count, "body not closed (PIPE-37)")
      refute_predicate(bodies.last, :closed?)
      assert_equal(1, bodies.first.release_count, "the superseded hop was released (PIPE-40)")
    end

    test "PIPE-37: an error status at PRE_REDIRECT raises the mapped error out of the pipeline" do
      transport = ->(req, _o, _c) { build_response(503, body: response_body("down"), request: req) }
      step = Dexpace::Pipeline::TransformStep.build(Dexpace::Recovery::ErrorMappingStep.build)
      pipeline = Dexpace::Pipeline.builder(transport: transport)
        .append(step, stage: STAGES::PRE_REDIRECT)
        .build

      error = assert_raises(Dexpace::ProtocolError) { pipeline.call(build_request) }

      assert_equal(503, error.status.code)
    end
  end
end
