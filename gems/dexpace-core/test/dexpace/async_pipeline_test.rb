# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/probe_step"
require_relative "../support/fake_async_transport"

# PIPE-28, PIPE-29, PIPE-30, PIPE-31, PIPE-32, PIPE-39 (the async direct half): the async mirror,
# its normalisation at the call site no phase-2 object reaches, and the terminal response-mapping
# operator (P4-36, P4-38).
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# runtime and PIPE-28 to PIPE-30 here, PIPE-31's operator below.
class DexpaceAsyncPipelineTest < DexpaceTestCase
  STAGES = Dexpace::Pipeline::Stages

  # Shared by every class below.
  module AsyncPipelines
    def setup
      super
      @transport = FakeAsyncTransport.new(response: "async_wire_res")
      @request = "req"
    end

    def builder(transport = @transport) = Dexpace::Pipeline::Builder.new(transport: transport)
    def passthrough = ->(req, cur) { cur.call(req) }
  end
  include AsyncPipelines

  # PIPE-28's "MUST NOT each re-derive ordering independently", asserted stage-for-stage and
  # step-for-step BY IDENTITY over the whole table rather than on its first row -- one Stages,
  # one Builder, one flatten (P4-30).
  test "PIPE-28: #build and #build_async produce identical entry tables by identity" do
    source = builder
      .append(passthrough, stage: STAGES::POST_SERDE)
      .append(ProbeStep.new(tag: :redirect, log: []), stage: STAGES::REDIRECT)
      .append(ProbeStep.new(tag: :pre, log: []), stage: STAGES::PRE_AUTH)
    sync_entries = source.build.entries
    async_entries = source.build_async.entries

    assert_equal(3, sync_entries.size)
    assert_equal(sync_entries.size, async_entries.size)
    sync_entries.zip(async_entries).each do |sync_entry, async_entry|
      assert_same(sync_entry.stage, async_entry.stage)
      assert_same(sync_entry.step, async_entry.step)
    end
    assert_equal(%i[redirect pre_auth post_serde], async_entries.map { |e| e.stage.name })
  end

  test "PIPE-39 & PIPE-26: .direct is a step-less async pipeline that conforms to the async seam" do
    pipeline = Dexpace::AsyncPipeline.direct(@transport)
    options = Dexpace::RequestOptions::EMPTY
    future = pipeline.call(@request, options)

    assert(Dexpace::AsyncTransport.conforms?(pipeline))
    assert_instance_of(Dexpace::Async::Future, future)
    assert_equal("async_wire_res", future.value)
    assert_same(options, @transport.calls.last[1])
    assert_same(@transport.completer.future, future, "the transport's own future, never re-wrapped")
    assert_empty(pipeline.steps)
  end

  test "an async step drives the cursor, forks through it, and hands its future straight back" do
    order = []
    forking = lambda do |req, cur|
      order << :redirect
      cur.fork.call(req).then { |res| "#{res}!" }
    end
    tail = lambda do |req, cur|
      order << :auth
      cur.call(req)
    end
    pipeline = builder.append(forking, stage: STAGES::REDIRECT)
      .append(tail, stage: STAGES::AUTH)
      .build_async

    assert_equal("async_wire_res!", pipeline.call(@request).value)
    assert_equal(%i[redirect auth], order)
  end

  test "PIPE-29 & PIPE-30: a step's synchronous StandardError becomes a failed future" do
    boom = ::RuntimeError.new("standard error in step")
    pipeline = builder.append(->(_r, _c) { raise boom }, stage: STAGES::PRE_AUTH).build_async

    future = pipeline.call(@request)

    assert_instance_of(Dexpace::Async::Future, future)
    caught = assert_raises(::RuntimeError) { future.value }

    assert_same(boom, caught, "the identical object: there is nothing to unwrap")
  end

  # The fatal family propagates synchronously, through an absent rescue arm; the class is
  # asserted rather than merely that something escaped.
  test "PIPE-30: a step's ScriptError propagates synchronously out of #call" do
    pipeline = builder.append(->(_r, _c) { raise NotImplementedError, "fatal" },
                              stage: STAGES::PRE_AUTH,).build_async

    assert_raises(NotImplementedError) { pipeline.call(@request) }
  end

  test "PIPE-30: the empty-pipeline transport dispatch is normalised too" do
    raising = ->(_r, _o, _c) { raise ::IOError, "socket" }
    pipeline = Dexpace::AsyncPipeline.direct(raising)

    future = pipeline.call(@request)

    assert_raises(::IOError) { future.value }
    fatal = Dexpace::AsyncPipeline.direct(->(_r, _o, _c) { raise ::LoadError })

    assert_raises(::LoadError) { fatal.call(@request) }
  end

  # P4-30's cost, checked where it can be: neither Step.conforms? nor AsyncTransport.conforms? can
  # see a return type, so a sync step or transport built through #build_async is caught by what
  # comes back -- the mirror of Bridge::SyncOver's check.
  test "an async step or transport returning a non-Future fails the future with SeamError" do
    sync_step = builder.append(->(_r, _c) { "a response, not a future" }, stage: STAGES::PRE_AUTH)
      .build_async

    error = assert_raises(Dexpace::SeamError) { sync_step.call(@request).value }

    assert_includes(error.message, "an async step must return a Dexpace::Async::Future, got String")

    sync_transport = Dexpace::AsyncPipeline.direct(->(_r, _o, _c) { :response })
    error = assert_raises(Dexpace::SeamError) { sync_transport.call(@request).value }

    assert_includes(error.message, "an async transport must return a Dexpace::Async::Future")
  end

  # PIPE-32's substantive clause constrains the postponed PRESET, not the runtime: PIPE-28's
  # identical staging policy means REDIRECT stays installable on the async path, and the
  # asymmetry is documented on the class (its last clause) rather than enforced here.
  test "PIPE-32 & PIPE-28: REDIRECT is installable on the async path, and no .standard exists" do
    pipeline = builder.append(passthrough, stage: STAGES::REDIRECT).build_async

    assert_equal(%i[redirect], pipeline.entries.map { |e| e.stage.name })
    refute_respond_to(Dexpace::AsyncPipeline, :standard, "postponed to phase 6b, Task 13a")
    refute_respond_to(Dexpace::Pipeline, :standard, "postponed to phase 6b, Task 13a")
  end

  test "PIPE-27 & PIPE-10: the async runtime latches on close and exposes frozen views" do
    pipeline = builder.append(passthrough, stage: STAGES::PRE_AUTH).build_async

    pipeline.close
    pipeline.close

    assert_predicate(pipeline, :closed?)
    refute_predicate(pipeline, :owned?)
    assert_predicate(pipeline.steps, :frozen?)
    assert_same(pipeline.entries, pipeline.entries)
    assert_same(@transport, pipeline.transport)
    assert_empty(Dexpace::AsyncPipeline.public_instance_methods(false).grep(/=\z/))
    assert_raises(NoMethodError) { Dexpace::AsyncPipeline.new }
  end

  # PIPE-31: the terminal response-mapping operator, over a bare Completer (P4-38).
  class MapResponseTest < DexpaceTestCase
    # A response with a real close latch, counting closes so PIPE-31's "idempotent double-close
    # tolerated" is asserted rather than assumed.
    class CountingResponse
      attr_reader :closes

      def initialize = @closes = 0
      def close = @closes += 1
      def closed? = @closes.positive?
    end

    test "applies the handler and THEN closes the response" do
      response = CountingResponse.new
      closed_when_handled = nil
      completer = Dexpace::Async::Completer.new
      mapped = Dexpace::AsyncPipeline.map_response(completer.future) do |res|
        closed_when_handled = res.closed?
        [:mapped, res]
      end

      completer.fulfil(response)

      assert_equal([:mapped, response], mapped.value)
      refute(closed_when_handled, "the handler sees the response open")
      assert_predicate(response, :closed?)
      assert_equal(1, response.closes)
    end

    test "a raising handler still closes the response and fails with the identical error" do
      response = CountingResponse.new
      expected = ::RuntimeError.new("handler error")
      completer = Dexpace::Async::Completer.new
      mapped = Dexpace::AsyncPipeline.map_response(completer.future) { raise expected }

      completer.fulfil(response)

      caught = assert_raises(::RuntimeError) { mapped.value }
      # The identical object, not merely an equal message: this port never wraps, so no
      # unwrapping step is needed and its absence is what this asserts.
      assert_same(expected, caught)
      assert_predicate(response, :closed?)
    end

    test "closing again is the caller's no-op, which the operator tolerates" do
      response = CountingResponse.new
      completer = Dexpace::Async::Completer.new
      mapped = Dexpace::AsyncPipeline.map_response(completer.future) { |res| res }

      completer.fulfil(response)
      mapped.value
      response.close

      assert_equal(2, response.closes, "the second close is the caller's and is tolerated")
    end

    test "a source failure is forwarded as the identical object, with no response to close" do
      boom = ::IOError.new("wire")
      completer = Dexpace::Async::Completer.new
      handled = false
      mapped = Dexpace::AsyncPipeline.map_response(completer.future) { |_res| handled = true }

      completer.fail(boom)

      assert_same(boom, assert_raises(::IOError) { mapped.value })
      refute(handled)
    end

    test "cancelling the mapped future cancels the source, carrying the reason" do
      seen_reason = nil
      source_completer = Dexpace::Async::Completer.new
      source_completer.on_cancel { |reason| seen_reason = reason }
      mapped = Dexpace::AsyncPipeline.map_response(source_completer.future) { |r| r }

      mapped.cancel(:client_abort)

      assert_predicate(source_completer.future, :cancelled?)
      assert_predicate(mapped, :cancelled?)
      assert_equal(:client_abort, seen_reason,
                   "the reason arrives as the on_cancel block's argument",)
    end

    test "requires a block and a future" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::AsyncPipeline.map_response(Dexpace::Async::Completer.new.future)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::AsyncPipeline.map_response(:not_a_future) { |r| r }
      end
    end

    test "maps a real pipeline's future end to end" do
      transport = FakeAsyncTransport.new(response: CountingResponse.new)
      pipeline = Dexpace::AsyncPipeline.direct(transport)

      mapped = Dexpace::AsyncPipeline.map_response(pipeline.call(:req)) { |res| res.closes + 0 }

      assert_equal(0, mapped.value, "handled while open")
      assert_predicate(transport.completer.future.value, :closed?)
    end
  end

  # Phase 6a's Task 8: the `bundle:` keyword on the async runtime.
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

    def settled(value)
      completer = Dexpace::Async::Completer.new
      completer.fulfil(value)
      completer.future
    end

    test "cursor bundle: AsyncPipeline#call seeds the cursor's bundle, NONE when omitted" do
      seen = []
      step = lambda { |req, cur|
        seen << cur.bundle
        cur.call(req)
      }
      transport = ->(_req, _opts, _canc) { settled(:response) }
      pipeline = Dexpace::Pipeline::Builder.new(transport: transport)
        .append(step, stage: Dexpace::Pipeline::Stages::PRE_RETRY)
        .build_async
      bundle = seeded

      assert_equal(:response, pipeline.call(request).value)
      assert_equal(:response, pipeline.call(request, bundle: bundle).value)
      assert_same(BUNDLE::NONE, seen[0])
      assert_same(bundle, seen[1])
    end

    test "cursor bundle: the empty async pipeline accepts the keyword and allocates no cursor" do
      pipeline = Dexpace::AsyncPipeline.direct(->(_r, _o, _c) { settled(:response) })

      assert_equal(:response, pipeline.call(request, bundle: seeded).value)
      assert(Dexpace::AsyncTransport.conforms?(pipeline))
    end
  end
end
