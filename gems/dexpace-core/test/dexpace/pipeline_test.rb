# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/probe_step"
require_relative "../support/forking_probe"
require_relative "../support/inline_executor"
require_relative "../support/fake_async_transport"

# PIPE-1, PIPE-2, PIPE-9, PIPE-10, PIPE-11, PIPE-25, PIPE-26, PIPE-27, PIPE-33 (clauses 1-4),
# PIPE-34, PIPE-35, PIPE-39 (the direct half): the synchronous runtime, and the two phase-2
# bridges composed over it (R13, P4-35).
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# ordering conformance clauses and the runtime's shape here, R12's two branches and the bridges
# below.
class DexpacePipelineTest < DexpaceTestCase
  STAGES = Dexpace::Pipeline::Stages

  # Shared by every class below.
  module Pipelines
    def setup
      super
      @transport = ->(_req, _opts, _canc) { "response_from_wire" }
      @request = "req"
    end

    def builder(transport = @transport) = Dexpace::Pipeline.builder(transport: transport)
    def probe(tag, log = []) = ProbeStep.new(tag: tag, log: log)
  end
  include Pipelines

  # PIPE-1's conformance clause verbatim: one probe per stage, SEND excluded, installed in a
  # SHUFFLED order. Installing them in declaration order would pass against an implementation
  # that preserved insertion order and derived nothing from the stage table, which is the one
  # thing PIPE-1 forbids. The seed is pinned and named in the failure message (testing/7ece0212).
  PIPE_1_SEED = 42

  test "PIPE-1: fifteen probes installed in shuffled order execute in strict stage order" do
    log = []
    stages = STAGES::ALL.reject(&:terminal?)
    shuffled = stages.shuffle(random: Random.new(PIPE_1_SEED))

    assert_equal(15, stages.size)
    refute_equal(stages, shuffled, "the install order must differ from the stage order")

    pipeline = builder
    shuffled.each { |stage| pipeline.append(probe(stage.name, log), stage: stage) }
    pipeline.build.call(@request)

    expected = stages.map { |s| [:enter, s.name] } + stages.reverse.map { |s| [:exit, s.name] }

    assert_equal(expected, log, "install order #{shuffled.map(&:name)} under seed #{PIPE_1_SEED}")
  end

  # PIPE-2's conformance clause verbatim, and the assertion that would fail if PRE_REDIRECT were
  # ordered INSIDE the redirect loop. It is the same fact PIPE-37 and design §6.2 both rest on.
  test "PIPE-2: a PRE_REDIRECT probe runs once while an AUTH probe runs twice under a fork" do
    pre_redirect_runs = 0
    auth_runs = 0
    pre_step = lambda do |r, c|
      pre_redirect_runs += 1
      c.call(r)
    end
    auth_step = lambda do |r, c|
      auth_runs += 1
      c.call(r)
    end

    pipeline = builder
      .append(pre_step, stage: STAGES::PRE_REDIRECT)
      .append(ForkingProbe.new(times: 2), stage: STAGES::REDIRECT)
      .append(auth_step, stage: STAGES::AUTH)
      .build
    pipeline.call(@request)

    assert_equal(1, pre_redirect_runs, "PRE_REDIRECT runs OUTSIDE the redirect loop (PIPE-2)")
    assert_equal(2, auth_runs, "AUTH runs once per fork (PIPE-2)")
  end

  # PIPE-26: the runtime IS the transport SPI, with and without per-call options (verified fact
  # 2). Nothing on Pipeline declares this; it is true of the #call signature, which is why the
  # assertion is phase 2's own predicate rather than an is_a? check -- and why the builder
  # itself satisfies SEAM-29's generic contract.
  test "PIPE-26: a built pipeline conforms to the transport seam, with one or three arguments" do
    pipeline = builder.append(probe(:s1), stage: STAGES::PRE_AUTH).build

    assert(Dexpace::Transport.conforms?(pipeline))
    assert_equal("response_from_wire", pipeline.call(@request))
    assert_equal("response_from_wire",
                 pipeline.call(@request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none),)
    assert_equal([pipeline.class], Dexpace::Builder.build_all([builder]).map(&:class))
  end

  test "PIPE-26: a pipeline nests as another pipeline's transport, and options survive it" do
    seen = nil
    wire = lambda do |_r, opts, _c|
      seen = opts
      "wire"
    end
    inner = builder(wire).append(probe(:inner), stage: STAGES::PRE_AUTH).build
    outer = builder(inner).append(probe(:outer), stage: STAGES::PRE_AUTH).build
    options = Dexpace::RequestOptions::EMPTY

    assert_equal("wire", outer.call(@request, options))
    assert_same(options, seen)
  end

  # PIPE-25's read-only ordered view, and PIPE-10's "immutable after construction" alongside it.
  # A frozen Array built once and returned by the same reference every call -- design §10.11's
  # computed-once rule, never a per-access dup, a wrapper, or a lazy Enumerator (an Enumerator
  # abandoned mid-#next never runs its ensure, and this is where it would be the idiomatic
  # answer).
  #
  # `pipeline.frozen?` is deliberately NOT asserted: PIPE-27's close latch writes an ivar, so a
  # frozen runtime would raise FrozenError on #close (plan open question 8). The absence of any
  # writer is asserted instead, which is what that assertion was protecting.
  test "PIPE-25 & PIPE-10: steps and entries are frozen, computed once, and nothing writes" do
    step = probe(:s1)
    source = builder.append(step, stage: STAGES::PRE_AUTH)
    pipeline = source.build

    assert_equal([step], pipeline.steps)
    assert_predicate(pipeline.steps, :frozen?)
    assert_predicate(pipeline.entries, :frozen?)
    assert_same(pipeline.steps, pipeline.steps)
    assert_same(pipeline.entries, pipeline.entries)
    assert_same(@transport, pipeline.transport)
    assert_raises(FrozenError) { pipeline.steps << :extra }
    assert_empty(Dexpace::Pipeline.public_instance_methods(false).grep(/=\z/))
    refute_respond_to(pipeline, :with)
    assert_raises(NoMethodError) { Dexpace::Pipeline.new }
  end

  # RECOV-14's discipline, applied to the runtime's step collection: a builder mutated after
  # #build cannot alter the runtime it produced.
  test "PIPE-10: later builder mutation does not reach a built runtime" do
    source = builder.append(probe(:s1), stage: STAGES::PRE_AUTH)
    pipeline = source.build
    source.append(probe(:s2), stage: STAGES::PRE_AUTH)

    assert_equal(1, pipeline.steps.size)
    assert_equal(2, source.entries.size)
  end

  test "PIPE-27: close latches, is idempotent, and never cascades to the terminal transport" do
    transport = Class.new do
      def initialize = @closed = false
      def call(_request, _options, _cancellation) = "res"
      def close = @closed = true
      def closed? = @closed
    end.new
    pipeline = Dexpace::Pipeline.direct(transport)

    pipeline.close
    pipeline.close

    assert_predicate(pipeline, :closed?)
    refute_predicate(pipeline, :owned?)
    # The NEGATIVE is the assertion: a test that closed once and checked nothing would pass
    # against a cascading close. And a closed pipeline still sends, because it released nothing.
    refute_predicate(transport, :closed?, "pipeline close must not cascade to transport (PIPE-27)")
    assert_equal("res", pipeline.call(@request))
  end

  # R12's two branches and PIPE-11's concurrency clause.
  class DispatchTest < DexpaceTestCase
    include Pipelines

    test "PIPE-9 & PIPE-39: .direct dispatches straight to the transport, arguments by identity" do
      options = Object.new.freeze
      cancellation = Object.new.freeze
      recorded = nil
      transport = lambda do |r, o, c|
        recorded = [r, o, c]
        "wire_res"
      end
      pipeline = Dexpace::Pipeline.direct(transport)

      assert_equal("wire_res", pipeline.call(@request, options, cancellation))
      assert_same(@request, recorded[0])
      assert_same(options, recorded[1])
      assert_same(cancellation, recorded[2])
      assert_empty(pipeline.steps)
      assert_empty(pipeline.entries)
    end

    test "a pipeline's transport is validated at build with phase 2's predicate" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Pipeline.direct(Object.new) }

      assert_includes(error.message, "responds to #call(request, options, cancellation)")
      assert_raises(Dexpace::InvalidArgumentError) { builder(->(_r) { "one arg" }).build }
    end

    # R12, the two allocation deltas. PIPE-9's trailing SHOULD is testable as a NON-allocation
    # rather than only as a behaviour (verified fact 11), and the non-empty delta is the assertion
    # that would fail if someone "optimised" the empty branch into the general one and removed the
    # cursor everywhere. Counting the cursor CLASS's instances rather than total allocations is
    # what keeps GC noise out of it. ObjectSpace.each_object is CRuby-specific; no v1 matrix row
    # is non-CRuby (phase 3a's IO-38 postponement, reopened only by a non-CRuby CI row), and the
    # test skips rather than fails elsewhere.
    test "PIPE-9 & PIPE-10: an empty pipeline allocates no cursor; a one-step pipeline allocates" do
      unless RUBY_ENGINE == "ruby" && ObjectSpace.respond_to?(:each_object)
        skip("ObjectSpace instance counting is CRuby-only (phase 3a's IO-38 postponement)")
      end
      empty = Dexpace::Pipeline.direct(@transport)
      stepped = builder.append(probe(:s1), stage: STAGES::PRE_AUTH).build
      cursors = -> { ObjectSpace.each_object(Dexpace::Pipeline::Cursor).count }

      GC.disable
      begin
        before_empty = cursors.call
        empty.call(@request)
        after_empty = cursors.call

        before_stepped = cursors.call
        stepped.call(@request)
        after_stepped = cursors.call
      ensure
        GC.enable
      end

      assert_equal(0, after_empty - before_empty, "an empty pipeline allocates no cursor (PIPE-9)")
      assert_operator(after_stepped - before_stepped, :>=, 1, "a step gets a cursor (PIPE-10)")
    end

    # PIPE-10's own clause and PIPE-11's: one shared step, sixteen concurrent sends, sixteen
    # distinct cursors, collected by identity -- a Cursor defines no ==, so equality would fall
    # through to identity anyway, and the assertion says what it means.
    test "PIPE-10 & PIPE-11: sixteen concurrent sends through one step get sixteen cursors" do
      seen = {}.compare_by_identity
      mutex = Mutex.new
      step = lambda do |r, c|
        mutex.synchronize { seen[c] = true }
        c.call(r)
      end
      pipeline = builder.append(step, stage: STAGES::PRE_AUTH).build

      threads = Array.new(16) { Thread.new { pipeline.call(@request) } }
      results = threads.map(&:value)

      assert_equal(16, seen.size, "16 concurrent calls allocate 16 distinct cursors (PIPE-10)")
      assert_equal(["response_from_wire"] * 16, results)
    end
  end

  # PIPE-33, PIPE-34 and PIPE-35: the bridges composed over a built pipeline, and the two seedings.
  class CompositionTest < DexpaceTestCase
    include Pipelines

    test "PIPE-33: async_over posts the whole pipeline once, as a single opaque unit" do
      pipeline = builder
      5.times { |i| pipeline.append(probe(:"p#{i}"), stage: STAGES::PRE_AUTH) }
      options = Dexpace::RequestOptions::EMPTY
      executor = InlineExecutor.new

      bridge = Dexpace::Transport.async_over(pipeline.build, executor: executor)
      future = bridge.call(@request, options, Dexpace::Cancellation.none)

      # Clause 2: the wrapped pipeline runs as ONE unit; its five steps never see the executor.
      # Clause 3: the options arrive at the wrapped send. Clause 1 is met by an absence -- core
      # ships no executor and this phase adds no default -- and clause 5, interrupt-mode
      # cancellation, is the unsatisfied one (design §10.5); there is no test of it because
      # there is no interrupt mode to test.
      assert_equal(1, executor.posts, "a five-step pipeline is one #post (PIPE-33)")
      assert_equal("response_from_wire", future.value)
    end

    test "PIPE-33: the options object reaches the transport by identity through the bridge" do
      seen = nil
      wire = lambda do |_r, opts, _c|
        seen = opts
        "wire"
      end
      pipeline = builder(wire).append(probe(:p), stage: STAGES::PRE_AUTH).build
      options = Dexpace::RequestOptions::EMPTY

      Dexpace::Transport.async_over(pipeline, executor: InlineExecutor.new)
        .call(@request, options, Dexpace::Cancellation.none).value

      assert_same(options, seen)
    end

    test "PIPE-34: sync_over blocks on the async result and preserves per-call options" do
      async_transport = FakeAsyncTransport.new(response: "async_wire_res")
      async_pipeline = Dexpace::Pipeline::Builder.new(transport: async_transport)
        .append(probe(:p1), stage: STAGES::PRE_AUTH)
        .build_async
      options = Dexpace::RequestOptions::EMPTY
      sync_bridge = Dexpace::AsyncTransport.sync_over(async_pipeline)

      assert_equal("async_wire_res", sync_bridge.call(@request, options, Dexpace::Cancellation.none))
      assert_same(options, async_transport.calls.last[1], "options survive the bridge (PIPE-34)")
    end

    # A cancelled token raises rather than blocking. The future must still be IN FLIGHT for the
    # token to be observed at all -- Future#await returns immediately on a settled one -- which is
    # what the fake's settle_later: mode is for. There is no interrupt-mode case here because
    # there is no interrupt mode: design §10.5.
    test "PIPE-34: a cancelled token surfaces as CancelledError instead of a wait" do
      deferred = FakeAsyncTransport.new(response: :never, settle_later: true)
      deferred_pipeline = Dexpace::AsyncPipeline.direct(deferred)
      source = Dexpace::Cancellation.source
      source.cancel(:client_abort)

      error = assert_raises(Dexpace::CancelledError) do
        Dexpace::AsyncTransport.sync_over(deferred_pipeline)
          .call(@request, Dexpace::RequestOptions::EMPTY, source.token)
      end

      assert_equal(:client_abort, error.reason)
      assert_predicate(deferred.completer.future, :cancelled?, "the in-flight future is cancelled")
    end

    # PIPE-35's own wording turned into two numbers: the same inner pipeline seeded both ways with
    # a new probe at PRE_RETRY. Under FLATTEN it runs TWICE (inside the redirect loop); under NEST
    # it runs ONCE (the inner pipeline is an opaque transport). It is the only assertion that
    # distinguishes the two constructors at all.
    test "PIPE-35: FLATTEN runs a new step inside the seeded loops, NEST runs it once outside" do
      base = builder.append(ForkingProbe.new(times: 2), stage: STAGES::REDIRECT).build
      flat_log = []
      nest_log = []

      flat = Dexpace::Pipeline::Builder.flattening(base)
      flat.append(probe(:probe, flat_log), stage: STAGES::PRE_RETRY)
      flat.build.call(@request)

      nest = Dexpace::Pipeline::Builder.nesting(base)
      nest.append(probe(:probe, nest_log), stage: STAGES::PRE_RETRY)
      nest.build.call(@request)

      assert_equal(2, flat_log.count(%i[enter probe]), "FLATTEN: inside the redirect loop")
      assert_equal(1, nest_log.count(%i[enter probe]), "NEST: outside the nested pipeline")
    end

    test "PIPE-35: flattening copies the entries, their names and the transport; nesting neither" do
      inner = ->(_r, _o, _c) { "inner" }
      base = builder(inner).append(probe(:a), stage: STAGES::PRE_AUTH, name: :a_probe).build

      flat = Dexpace::Pipeline::Builder.flattening(base)
      nest = Dexpace::Pipeline::Builder.nesting(base)

      assert_equal(base.entries, flat.entries)
      assert_equal([:a_probe], flat.entries.map(&:name))
      assert_same(inner, flat.build.transport)
      assert_empty(nest.entries)
      assert_same(base, nest.build.transport)
    end
  end

  # Phase 6a's Task 8: the `bundle:` keyword seeds Cursor#bundle for one call.
  class BundleSeedingTest < DexpaceTestCase
    BUNDLE = Dexpace::Instrumentation::Bundle

    def seeded
      BUNDLE.build(trace_id: "a" * 32, span_id: "b" * 16,
                   flavour: Dexpace::Instrumentation::TraceIdFlavour::W3C,)
    end

    def request
      Dexpace::Request.build(method: Dexpace::Method::GET, url: "https://example.test/",
                             headers: Dexpace::Headers::EMPTY,)
    end

    test "cursor bundle: Pipeline#call seeds the cursor's bundle, NONE when omitted" do
      seen = []
      step = lambda { |req, cur|
        seen << cur.bundle
        cur.call(req)
      }
      transport = ->(_req, _opts, _canc) { :response }
      pipeline = Dexpace::Pipeline::Builder.new(transport: transport)
        .append(step, stage: Dexpace::Pipeline::Stages::PRE_RETRY)
        .build
      bundle = seeded

      pipeline.call(request)
      pipeline.call(request, bundle: bundle)
      pipeline.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none,
                    bundle: bundle,)

      assert_same(BUNDLE::NONE, seen[0])
      assert_same(bundle, seen[1])
      assert_same(bundle, seen[2])
    end

    test "cursor bundle: the empty pipeline dispatches with no cursor and accepts the keyword" do
      calls = []
      transport = lambda { |req, opts, canc|
        calls << [req, opts, canc]
        :response
      }
      pipeline = Dexpace::Pipeline.direct(transport)

      assert_equal(:response, pipeline.call(request, bundle: seeded))
      assert_equal(1, calls.size)
    end

    test "cursor bundle / SEAM-11: a Pipeline is still a Transport by the duck type" do
      pipeline = Dexpace::Pipeline.direct(->(_r, _o, _c) { :response })

      assert(Dexpace::Transport.conforms?(pipeline))
      assert(Dexpace::Registry.callable?(pipeline, arity: 3))
    end

    test "cursor bundle: a non-Bundle is refused before any step runs" do
      ran = false
      step = lambda { |req, cur|
        ran = true
        cur.call(req)
      }
      pipeline = Dexpace::Pipeline::Builder.new(transport: ->(*) { :r })
        .append(step, stage: Dexpace::Pipeline::Stages::PRE_RETRY)
        .build

      assert_raises(Dexpace::InvalidArgumentError) { pipeline.call(request, bundle: :none) }
      refute(ran)
    end
  end
end
