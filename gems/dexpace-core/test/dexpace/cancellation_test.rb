# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# SEAM-11 and SEAM-16's third argument, SEAM-13's contract, SEAM-18's interruption clause and
# SEAM-30's trigger. The state lives on the Source and the token is a facade over one or more of
# them -- the same split as Completer/Future, and for the same reason: Ruby has no package-private
# visibility, so the alternative is a `send` through the boundary this pair exists to draw.
#
# Three classes, one per behaviour group, because Metrics/ClassLength caps a class at 100 lines:
# the token's own contract here, composition in Composition, and registrations in Subscriptions.
class DexpaceCancellationTest < DexpaceTestCase
  test "none is a shared token that can never be cancelled" do
    assert_same(Dexpace::Cancellation.none, Dexpace::Cancellation.none)
    refute_predicate(Dexpace::Cancellation.none, :cancelled?)
    assert_nil(Dexpace::Cancellation.none.reason)
    assert_nil(Dexpace::Cancellation.none.check!)
  end

  test "a source cancels its token once and the first reason wins" do
    source = Dexpace::Cancellation.source
    seen = []
    source.token.on_cancel { |reason| seen << reason }

    refute_predicate(source.token, :cancelled?)
    assert(source.cancel(:deadline))
    refute(source.cancel(:something_else), "cancel is idempotent; the first reason wins")

    assert_predicate(source.token, :cancelled?)
    assert_equal(:deadline, source.token.reason)
    assert_equal([:deadline], seen)
  end

  test "on_cancel fires immediately when the token is already cancelled" do
    source = Dexpace::Cancellation.source
    source.cancel(:late)
    seen = []

    source.token.on_cancel { |reason| seen << reason }

    assert_equal([:late], seen)
  end

  test "check! raises CancelledError carrying the reason object" do
    source = Dexpace::Cancellation.source
    source.cancel(:stop)

    error = assert_raises(Dexpace::CancelledError) { source.token.check! }

    assert_equal(:stop, error.reason)
  end

  test "a deliberate nil reason is still a cancellation" do
    source = Dexpace::Cancellation.source
    seen = []
    source.token.on_cancel { |reason| seen << reason }

    source.cancel

    assert_predicate(source.token, :cancelled?)
    assert_nil(source.token.reason)
    assert_equal([nil], seen)
  end

  test "every token is frozen, none included, and none's on_cancel is inert" do
    assert_predicate(Dexpace::Cancellation.none, :frozen?)
    assert_predicate(Dexpace::Cancellation.source.token, :frozen?)
    assert_predicate(Dexpace::Cancellation.any(Dexpace::Cancellation.source.token), :frozen?)

    Dexpace::Cancellation.none.on_cancel { flunk("a token with no sources can never fire") }
  end

  test "none's on_cancel still answers a handle, so a caller need not special-case it" do
    assert_nil(Dexpace::Cancellation.none.on_cancel { flunk("never fires") }.detach)
  end

  test "on_cancel without a block is a caller mistake" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Cancellation.source.token.on_cancel }
  end

  test "a source's on_cancel requires a block, exactly as its token's does" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Cancellation.source.on_cancel }
  end

  test "new is private; .none, .source, .over and .any are the factories" do
    refute_respond_to(Dexpace::Cancellation, :new)
    assert_respond_to(Dexpace::Cancellation, :none)
    assert_respond_to(Dexpace::Cancellation, :source)
    assert_respond_to(Dexpace::Cancellation, :over)
    assert_respond_to(Dexpace::Cancellation, :any)
  end

  # Composition: .any, .over and #merged_with, and the winner rule.
  class Composition < DexpaceTestCase
    # The reason is the one of the source that cancelled first in TIME, not the first cancelled
    # source in list order. `second` is second in the list and first in time, and #reason must
    # agree with what #on_cancel was handed -- a composed token that disagrees with its own
    # handler is worse than one with no reason at all.
    test "any composes tokens and reports the reason of whichever cancelled first in time" do
      first = Dexpace::Cancellation.source
      second = Dexpace::Cancellation.source
      both = Dexpace::Cancellation.any(first.token, second.token)
      seen = []
      both.on_cancel { |reason| seen << reason }

      refute_predicate(both, :cancelled?)
      second.cancel(:second)
      first.cancel(:first)

      assert_predicate(both, :cancelled?)
      assert_equal(:second, both.reason)
      assert_equal([:second], seen)
      raised = assert_raises(Dexpace::CancelledError) { both.check! }
      assert_equal(:second, raised.reason)
    end

    test "the winner is the source that cancelled first in time, across more than two" do
      first, second, third = Array.new(3) { Dexpace::Cancellation.source }
      token = Dexpace::Cancellation.any(first.token, second.token, third.token)
      seen = []
      token.on_cancel { |reason| seen << reason }

      third.cancel(:third)
      second.cancel(:second)
      first.cancel(:first)

      assert_equal(:third, token.reason)
      assert_equal([:third], seen)
    end

    test "sources is protected, so only another token composes on it" do
      refute_respond_to(Dexpace::Cancellation.source.token, :sources)
      assert_raises(::NoMethodError) { Dexpace::Cancellation.source.token.sources }
    end

    test "any of nothing, and any of none, is none" do
      assert_same(Dexpace::Cancellation.none, Dexpace::Cancellation.any)
      assert_same(Dexpace::Cancellation.none, Dexpace::Cancellation.any(Dexpace::Cancellation.none))
    end

    test "any de-duplicates a source seen through two tokens" do
      source = Dexpace::Cancellation.source
      seen = []
      token = Dexpace::Cancellation.any(source.token, Dexpace::Cancellation.any(source.token))
      token.on_cancel { |reason| seen << reason }

      source.cancel(:once)

      assert_equal([:once], seen)
    end

    test "any refuses anything that is not a token, naming the class" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Cancellation.any(:nope) }

      assert_match(/Symbol/, error.message)
    end

    # .over is public so phase 5's deadline source can compose here, so it validates like the
    # other two composition entry points. Unguarded it builds a token that raises NoMethodError
    # from inside #cancelled? later, at a call site with no idea what went wrong.
    test "over refuses anything that is not a source, naming the class" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Cancellation.over(:nope) }

      assert_match(/Symbol/, error.message)
    end

    test "over of nothing is none, and over of a source reads that source" do
      source = Dexpace::Cancellation.source

      assert_same(Dexpace::Cancellation.none, Dexpace::Cancellation.over)
      refute_predicate(Dexpace::Cancellation.over(source), :cancelled?)
      source.cancel(:go)

      assert_predicate(Dexpace::Cancellation.over(source), :cancelled?)
    end

    test "merged_with refuses anything that is not a token" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Cancellation.source.token.merged_with(:nope)
      end
    end
  end

  # Registrations: every block fires, exactly once, detachably, and a raising one drops no other.
  class Subscriptions < DexpaceTestCase
    # A shared "something already fired" flag would drop every registration after the first, which
    # is what makes a second waiter on one token block forever (SEAM-18).
    test "every registered block fires, not just the first" do
      source = Dexpace::Cancellation.source
      seen = []
      source.token.on_cancel { seen << :first }
      source.token.on_cancel { seen << :second }

      source.cancel(:go)

      assert_equal(%i[first second], seen)
    end

    # The leak has two halves and either alone is enough to retain a response per request, so
    # both are asserted here against ONE long-lived source. (1) A token subscribes only when a
    # caller registers a callback, so composing costs nothing that outlives the token; subscribing
    # at construction to latch the winner retains one closure per composition. (2) A registration
    # made by Completer#await is detached when the await ends, so a bounded wait retains nothing
    # on an unbounded source; without the detach the closure reaches the Completer and therefore
    # the response it settled with. `.any(client_token, per_call_token)` plus
    # `value(cancellation:)` is exactly what `.any` is for and what phase 5a's deadline: keyword
    # (Task 8) will do on every request.
    #
    # The second half awaits a future that is NOT yet settled, deliberately: Completer#await
    # returns before arming anything when the future has already settled, so a test that awaits a
    # settled future passes with the leak fully present.
    test "neither composing nor awaiting retains a callback on a long-lived source" do
      client = Dexpace::Cancellation.source

      200.times { Dexpace::Cancellation.any(client.token, Dexpace::Cancellation.source.token) }

      assert_equal(0, client.instance_variable_get(:@hooks).size,
                   "composition subscribed to a source at construction",)

      completer = Dexpace::Async::Completer.new
      token = Dexpace::Cancellation.any(client.token, Dexpace::Cancellation.source.token)
      producer = ::Thread.new do
        sleep(0.02)
        completer.fulfil(Object.new)
      end

      completer.future.value(cancellation: token)
      producer.join

      assert_equal(0, client.instance_variable_get(:@hooks).size,
                   "the await armed a hook on a client-lifetime source and never detached it",)
    end

    test "on_cancel returns a handle that detaches exactly its own registration" do
      source = Dexpace::Cancellation.source
      seen = []
      kept = source.token.on_cancel { seen << :kept }
      detached = source.token.on_cancel { seen << :detached }

      detached.detach

      assert_nil(detached.detach, "detach is idempotent and returns nil")
      source.cancel(:go)

      assert_equal([:kept], seen)
      assert_nil(kept.detach, "detaching after the source has cancelled is a no-op")
    end

    test "a composed token's handle detaches from every source it observes" do
      first = Dexpace::Cancellation.source
      second = Dexpace::Cancellation.source
      token = Dexpace::Cancellation.any(first.token, second.token)

      token.on_cancel { flunk("detached before either source cancelled") }.detach
      first.cancel(:one)
      second.cancel(:two)

      assert_equal(0, first.instance_variable_get(:@hooks).size)
      assert_equal(0, second.instance_variable_get(:@hooks).size)
    end

    # A raising handler must not silence the ones registered after it. That is the same SEAM-18
    # failure as "a second waiter on one token blocks forever", reached from the write side: the
    # second waiter's handler is never called at all.
    test "one raising handler does not drop the handlers registered after it" do
      source = Dexpace::Cancellation.source
      seen = []
      source.token.on_cancel { seen << :first }
      source.token.on_cancel { raise ::IOError, "a handler blew up" }
      source.token.on_cancel { seen << :third }

      assert_raises(::IOError) { source.cancel(:go) }

      assert_equal(%i[first third], seen)
      assert_predicate(source, :cancelled?, "the state was published before any handler ran")
      assert_equal(:go, source.reason)
    end

    # Phase 2's postponement, picked up by phase 4b (Task 2): the failures AFTER the first are no
    # longer dropped -- each is attached to the first through Dexpace.attach_suppressed, in
    # registration order. The one test that distinguishes the old code from the new, and the
    # one place it lives: all three call sites reach the same Hooks.notify. The primary is a
    # bare ::IOError, so the carrier is Dexpace::Suppressible and not Dexpace::Error (P4-12).
    test "two raising handlers surface the first with the second on its suppressed trail" do
      source = Dexpace::Cancellation.source
      first = ::IOError.new("first handler failed")
      second = ::RuntimeError.new("second handler failed")
      seen = []
      source.token.on_cancel { raise first }
      source.token.on_cancel { seen << :healthy }
      source.token.on_cancel { raise second }

      caught = assert_raises(::IOError) { source.cancel(:go) }

      assert_same(first, caught)
      assert_equal([:healthy], seen)
      assert_kind_of(Dexpace::Suppressible, caught)
      refute_kind_of(Dexpace::Error, caught)
      assert_equal(1, Dexpace.suppressed(caught).size)
      assert_same(second, Dexpace.suppressed(caught).first)
    end

    # The re-raise carries `cause: nil`: notify re-raises an error it has been CARRYING since an
    # earlier iteration, and a bare `raise` there would hand it the caller's in-flight $! as a
    # #cause whenever a hook list is drained from inside a rescue (verified fact 5). The fixture
    # is a CONSTRUCTED error raised with an explicit `cause: nil` by the hook, so it reaches
    # notify with no cause -- the only shape the spelling changes the outcome for.
    test "the surfaced handler failure acquires no cause from the caller's in-flight exception" do
      source = Dexpace::Cancellation.source
      first = ::IOError.new("carried")
      source.token.on_cancel { raise first, cause: nil }
      source.token.on_cancel { raise ::RuntimeError, "later", cause: nil }

      caught = begin
        raise "unrelated caller in-flight exception"
      rescue ::StandardError
        begin
          source.cancel(:go)
        rescue ::IOError => error
          error
        end
      end

      assert_same(first, caught)
      assert_nil(caught.cause, "Hooks.notify must not be the thing that adds a cause")
    end
  end
end
