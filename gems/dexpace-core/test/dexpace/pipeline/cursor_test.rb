# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/forking_probe"

# PIPE-10, PIPE-11, PIPE-12, PIPE-13, PIPE-14, PIPE-15, PIPE-16, PIPE-17, PIPE-40, R10, R11: the
# per-invocation cursor, its single-use latch, its pillar-only fork and its (stage, key) state.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the drive
# (PIPE-12 to PIPE-14, PIPE-17) here, the fork (PIPE-15, PIPE-16, PIPE-40, P4-39) and R11's five
# state assertions below.
class DexpacePipelineCursorTest < DexpaceTestCase
  STAGES = Dexpace::Pipeline::Stages
  CURSOR = Dexpace::Pipeline::Cursor

  # SyncDriver is a private_constant, so `Dexpace::Pipeline::SyncDriver` raises NameError from out
  # here; const_get is the documented way through and is the hole the design already names on
  # Cursor.build's drive: keyword. Reaching for it is what lets these tests drive a cursor with no
  # Pipeline runtime in the picture, which is the whole point of Task 6 preceding Task 8.
  SYNC_DRIVER = Dexpace::Pipeline.const_get(:SyncDriver)

  # The runtime surface a driver reads: a frozen entry table and a terminal transport, and nothing
  # else. Standing in for Dexpace::Pipeline here keeps this suite independent of the runtime.
  class DummySyncPipeline
    attr_reader :entries, :transport

    def initialize(entries, transport)
      @entries = entries.freeze
      @transport = transport
    end
  end

  # The narrowest stand-in for a Response that PIPE-40 needs: something with a close latch. Phase
  # 3's Body and Response are not involved -- no bytes cross this phase (design, Testing strategy).
  class FakeCloseable
    def initialize = @closed = false
    def close = @closed = true
    def closed? = @closed
  end

  # Shared by every class below.
  module Cursors
    def setup
      super
      @request = "original_request"
      @options = Object.new.freeze
      @cancellation = Object.new.freeze
      @transport = ->(req, _opts, _canc) { "response_for_#{req}" }
    end

    def entry(stage, step) = Dexpace::Pipeline::Entry.build(stage: stage, step: step)

    def cursor_over(entries, transport = @transport)
      CURSOR.build(
        drive: SYNC_DRIVER.new(DummySyncPipeline.new(entries, transport)),
        request: @request, options: @options, cancellation: @cancellation,
      )
    end
  end
  include Cursors

  test "Cursor.new is private and .build produces the root cursor bound to no entry" do
    assert_raises(NoMethodError) { CURSOR.new }
    root = cursor_over([])

    assert_same(@request, root.request)
    assert_same(@options, root.options)
    assert_same(@cancellation, root.cancellation)
    refute_predicate(root, :spent?)
    refute_predicate(root, :may_fork?, "the root cursor is a cursor and is not a step's cursor")
  end

  # PIPE-13's terminal clause and PIPE-17: past the last entry the transport is called with the
  # in-flight request, the caller's options and the token, all by identity.
  test "PIPE-13 & PIPE-17: an exhausted cursor dispatches to the transport by identity" do
    recorded = nil
    wire = lambda do |req, opts, canc|
      recorded = [req, opts, canc]
      "wire"
    end

    assert_equal("wire", cursor_over([], wire).call(@request))
    assert_same(@request, recorded[0])
    assert_same(@options, recorded[1])
    assert_same(@cancellation, recorded[2])
  end

  test "PIPE-13: #call with no argument drives with the in-flight request" do
    recorded = nil
    wire = lambda do |req, _opts, _canc|
      recorded = req
      "wire"
    end

    cursor_over([], wire).call

    assert_same(@request, recorded)
  end

  test "PIPE-12: a short-circuiting step reaches neither downstream steps nor the transport" do
    transport_called = false
    downstream_called = false
    step1 = ->(_req, _cur) { "synthetic_response" }
    step2 = lambda do |req, cur|
      downstream_called = true
      cur.call(req)
    end
    wire = lambda do |_r, _o, _c|
      transport_called = true
      "wire"
    end

    res = cursor_over([entry(STAGES::PRE_AUTH, step1), entry(STAGES::AUTH, step2)], wire).call

    assert_equal("synthetic_response", res)
    refute(downstream_called)
    refute(transport_called)
  end

  # PIPE-13: forward-only, single-use. Asserted on the raised object, never with
  # assert_nothing_raised.
  test "PIPE-13 & PIPE-15: a second sequential #call raises PipelineError and spent? is true" do
    cursor = cursor_over([])

    refute_predicate(cursor, :spent?)
    cursor.call(@request)

    assert_predicate(cursor, :spent?)
    error = assert_raises(Dexpace::PipelineError) { cursor.call(@request) }

    assert_includes(error.message, "cursor has already been invoked and cannot be reused (PIPE-15)")
  end

  test "PIPE-14: a substituted request sticks for every downstream step and the transport" do
    seen = []
    sub_req = "substituted_request"
    step1 = ->(_req, cur) { cur.call(sub_req) }
    recorder = lambda do |req, cur|
      seen << req
      cur.call(req)
    end
    wire = lambda do |req, _o, _c|
      seen << req
      "wire"
    end
    entries = [entry(STAGES::PRE_RETRY, step1), entry(STAGES::RETRY, recorder),
               entry(STAGES::POST_AUTH, recorder),]

    cursor_over(entries, wire).call(@request)

    assert_equal(3, seen.size)
    seen.each { |req| assert_same(sub_req, req) }
    refute_includes(seen, @request, "the original must not be retained anywhere on the drive")
  end

  test "R11 / R10: the root cursor cannot fork either, and says why" do
    error = assert_raises(Dexpace::PipelineError) { cursor_over([]).fork }

    assert_includes(error.message, "bound to no entry and cannot fork (PIPE-15)")
  end

  test "#fork refuses a state: that is not a Hash" do
    step = ->(_req, cur) { cur.fork(state: "cross_origin") }

    assert_raises(Dexpace::InvalidArgumentError) do
      cursor_over([entry(STAGES::REDIRECT, step)]).call(@request)
    end
  end

  # PIPE-15, PIPE-16, PIPE-40 and P4-39: the fork.
  class ForkTest < DexpaceTestCase
    include Cursors

    # R11's disjointness rule (P4-39), and the assertion that fails if someone re-admits PIPE-15's
    # mixed drive-then-fork shape.
    test "PIPE-15 / P4-39: #fork after #call on the same pillar cursor is rejected" do
      step = lambda do |req, cur|
        cur.call(req)
        cur.fork
      end

      error = assert_raises(Dexpace::PipelineError) do
        cursor_over([entry(STAGES::REDIRECT, step)]).call(@request)
      end

      assert_includes(
        error.message,
        "cursor is spent and cannot be forked; #call and #fork are disjoint (PIPE-15)",
      )
    end

    test "PIPE-16 & PIPE-17: forks re-run the whole tail independently, options by identity" do
      downstream_options = []
      downstream_spent = []
      downstream_cursors = []
      step2 = lambda do |req, cur|
        downstream_options << cur.options
        downstream_cursors << cur
        response = cur.call(req)
        downstream_spent << cur.spent?
        response
      end
      entries = [entry(STAGES::REDIRECT, ForkingProbe.new(times: 2)), entry(STAGES::AUTH, step2)]

      cursor_over(entries).call(@request)

      # PIPE-16: the whole downstream tail re-runs from the fork's position, so AUTH is invoked
      # once per drive. A test that only asserted the response came back would pass against a
      # cursor that resumed PAST the tail on the second drive -- the exact defect PIPE-15
      # describes.
      assert_equal(2, downstream_options.size)
      assert_equal([true, true], downstream_spent)
      refute_same(downstream_cursors[0], downstream_cursors[1], "forks must advance independently")
      # PIPE-17: shared, not copied-and-diverged. assert_equal would pass against a per-fork
      # rebuild.
      assert_same(@options, downstream_options[0])
      assert_same(@options, downstream_options[1])
    end

    # PIPE-16's "share the immutable per-call options" and "carry the current in-flight request",
    # read off the fork itself rather than downstream.
    test "PIPE-16: a fork carries the parent's request, options and token, and is not spent" do
      fork = nil
      step = lambda do |_req, cur|
        fork = cur.fork
        fork.call
      end

      cursor_over([entry(STAGES::RETRY, step)]).call(@request)

      assert_same(@request, fork.request)
      assert_same(@options, fork.options)
      assert_same(@cancellation, fork.cancellation)
      assert_predicate(fork, :spent?)
    end

    test "PIPE-40: a re-driving step closes each superseded response, returns the last unclosed" do
      responses = []
      wire = lambda do |_r, _o, _c|
        response = FakeCloseable.new
        responses << response
        response
      end
      probe = ForkingProbe.new(times: 3)

      returned = cursor_over([entry(STAGES::REDIRECT, probe)], wire).call(@request)

      assert_equal(3, responses.size)
      assert_equal(3, probe.drives)
      assert_same(responses.last, returned)
      assert_equal([responses[0], responses[1]], probe.closed_responses)
      assert_predicate(responses[0], :closed?)
      assert_predicate(responses[1], :closed?)
      refute_predicate(returned, :closed?, "close-responsibility passes outward (PIPE-40)")
    end

    test "R11 assertion 3: a non-pillar stage cannot fork, and may_fork? says so first" do
      asked = nil
      step = lambda do |_req, cur|
        asked = cur.may_fork?
        cur.fork
      end

      error = assert_raises(Dexpace::PipelineError) do
        cursor_over([entry(STAGES::PRE_AUTH, step)]).call(@request)
      end

      assert_includes(
        error.message, "stage pre_auth is not a configurable pillar and cannot fork (PIPE-15)",
      )
      refute(asked)
    end

    test "may_fork? is true for a pillar step's cursor until it is spent" do
      before = after = nil
      step = lambda do |req, cur|
        before = cur.may_fork?
        response = cur.fork.call(req)
        after = cur.may_fork?
        response
      end

      cursor_over([entry(STAGES::RETRY, step)]).call(@request)

      assert(before)
      assert(after, "forking does not spend the parent; only #call does")

      spent_step = lambda do |req, cur|
        response = cur.call(req)
        after = cur.may_fork?
        response
      end
      cursor_over([entry(STAGES::RETRY, spent_step)]).call(@request)

      refute(after, "a spent cursor answers false, so a step can ask rather than rescue")
    end
  end

  # R11's five assertions, the last two the negatives a positive-only suite would miss.
  class StateTest < DexpaceTestCase
    include Cursors

    # R11 assertion 1. The negative is a statement about the SURFACE, not about a branch (P4-29):
    # "writable only by the pillar step that created the fork" is implemented as an unwritable
    # object plus a fork-time argument, so there is no check to bypass. The runtime surface
    # manifest pins the same fact from the other side (Task 11).
    test "R11 assertion 1: the cursor exposes no state-setting method at all" do
      methods = CURSOR.public_instance_methods(false)

      assert_empty(methods.grep(/=\z/), "no writer of any name may appear on Cursor")
      # #bundle is phase 6a's Task 8 reader; the pin grew by one reader and no writer.
      assert_equal(%i[bundle call cancellation fork may_fork? options request spent? state],
                   methods.sort,)
    end

    test "R11 assertion 2: the reachable state map is frozen, and unwritten stages share one" do
      cursor = cursor_over([])
      state = cursor.state(STAGES::REDIRECT)

      assert_predicate(state, :frozen?)
      assert_raises(FrozenError) { state[:cross_origin] = false }
      assert_same(state, cursor.state(STAGES::AUTH), "one shared frozen empty hash, no allocation")
    end

    test "#state refuses anything but a Stage, so a typo cannot read as an empty slot" do
      cursor = cursor_over([])

      assert_raises(Dexpace::InvalidArgumentError) { cursor.state(:redirect) }
      assert_raises(Dexpace::InvalidArgumentError) { cursor.state(nil) }
    end

    # R11 assertion 4, and it is the assertion the (stage, key) namespacing exists for. Written
    # against Stages::REDIRECT and Stages::RETRY BY NAME because REDIR-11's cross-origin marker,
    # AUTH-29's reading of it and design section 10.15's "forgery becomes structurally impossible
    # rather than defended against" all rest on exactly this: a RETRY pillar step sits between
    # REDIRECT and AUTH in PIPE-2's order and may fork, so under a FLAT keyed map its fork could
    # carry a cross_origin AUTH cannot distinguish from REDIRECT's. Under a flat map this test
    # fails. A phase-6 author who changes the mechanism meets this comment.
    test "R11 assertion 4: a downstream pillar cannot alter an upstream pillar's slot" do
      auth_seen_redirect = auth_seen_retry = nil
      redirect_step = ForkingProbe.new(times: 1, state_per_drive: [{ cross_origin: true }])
      retry_state = { cross_origin: false, attempt: 1 }
      retry_step = ForkingProbe.new(times: 1, state_per_drive: [retry_state])
      auth_step = lambda do |req, cur|
        auth_seen_redirect = cur.state(STAGES::REDIRECT)
        auth_seen_retry = cur.state(STAGES::RETRY)
        cur.call(req)
      end
      entries = [entry(STAGES::REDIRECT, redirect_step), entry(STAGES::RETRY, retry_step),
                 entry(STAGES::AUTH, auth_step),]

      cursor_over(entries).call(@request)

      assert_equal({ cross_origin: true }, auth_seen_redirect)
      assert_equal({ cross_origin: false, attempt: 1 }, auth_seen_retry)
      assert_predicate(auth_seen_redirect, :frozen?)
    end

    test "R11 assertion 5: a fork's write reaches neither its parent nor a sibling fork" do
      step = Class.new do
        attr_reader :before_state, :parent_state, :sibling_state, :first_state

        def call(req, cur)
          @before_state = cur.state(Dexpace::Pipeline::Stages::REDIRECT)
          first = cur.fork(state: { hop: 1 })
          @first_state = first.state(Dexpace::Pipeline::Stages::REDIRECT)
          @parent_state = cur.state(Dexpace::Pipeline::Stages::REDIRECT)
          second = cur.fork(state: { hop: 2 })
          @sibling_state = second.state(Dexpace::Pipeline::Stages::REDIRECT)
          second.call(req)
        end
      end.new

      cursor_over([entry(STAGES::REDIRECT, step)]).call(@request)

      # The same frozen object, not merely an equal one: a fork that mutated the parent's map in
      # place would still be assert_equal-clean here (verified fact 4's FrozenError is the other
      # half).
      assert_same(step.before_state, step.parent_state)
      assert_empty(step.parent_state)
      assert_equal({ hop: 1 }, step.first_state)
      # A second fork from the same parent inherits the parent's state, never the first fork's --
      # which is how REDIR-11's marker expires for free between hops (design §6.2).
      assert_equal({ hop: 2 }, step.sibling_state)
    end

    # A fork of a fork inherits the accumulated slot and merges over it, key by key.
    test "R11: a nested fork inherits and merges its owner's slot" do
      seen = nil
      step = lambda do |req, cur|
        inner = cur.fork(state: { a: 1, b: 1 }).fork(state: { b: 2 })
        seen = inner.state(Dexpace::Pipeline::Stages::REDIRECT)
        inner.call(req)
      end

      cursor_over([entry(STAGES::REDIRECT, step)]).call(@request)

      assert_equal({ a: 1, b: 2 }, seen)
    end

    test "R11: an empty or nil state: forks without allocating a new map" do
      parent_state = fork_state = nil
      step = lambda do |req, cur|
        parent_state = cur.state(Dexpace::Pipeline::Stages::REDIRECT)
        fork_state = cur.fork(state: {}).state(Dexpace::Pipeline::Stages::REDIRECT)
        cur.fork(state: nil).call(req)
      end

      cursor_over([entry(STAGES::REDIRECT, step)]).call(@request)

      assert_same(parent_state, fork_state)
    end
  end
end
