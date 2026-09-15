# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_async_transport"
require "dexpace"

# SEAM-18's async-to-sync half, clause by clause.
class DexpaceBridgeSyncOverTest < DexpaceTestCase
  test "returns the delivered response" do
    response = Object.new
    sync = Dexpace::AsyncTransport.sync_over(FakeAsyncTransport.new(response: response))

    assert_same(response, sync.call(:request, nil, nil))
  end

  test "surfaces the original failure, not a wrapper" do
    boom = ::IOError.new("reset")
    sync = Dexpace::AsyncTransport.sync_over(FakeAsyncTransport.new(raises: boom))

    caught = assert_raises(::IOError) { sync.call(:request, nil, nil) }

    assert_same(boom, caught, "SEAM-18: the pivot never wraps, so there is nothing to unwrap")
  end

  test "honours cancellation by cancelling the in-flight future and raising" do
    transport = FakeAsyncTransport.new(response: :never, settle_later: true)
    sync = Dexpace::AsyncTransport.sync_over(transport)
    source = Dexpace::Cancellation.source
    canceller = ::Thread.new do
      sleep(0.02)
      source.cancel(:interrupted)
    end

    error = assert_raises(Dexpace::CancelledError) { sync.call(:request, nil, source.token) }

    assert_equal(:interrupted, error.reason)
    assert_predicate(transport.completer.future, :cancelled?,
                     "the in-flight future was cancelled, not orphaned",)
    canceller.join
  end

  test "threads the exact options object through" do
    options = Dexpace::RequestOptions::EMPTY
    transport = FakeAsyncTransport.new(response: :ok)
    Dexpace::AsyncTransport.sync_over(transport).call(:request, options, nil)

    assert_same(options, transport.calls.first[1])
  end

  test "refuses an async transport that does not return a future" do
    sync = Dexpace::AsyncTransport.sync_over(->(_r, _o, _c) { :not_a_future })

    error = assert_raises(Dexpace::SeamError) { sync.call(:request, nil, nil) }

    assert_match(/must return a Dexpace::Async::Future/, error.message)
  end

  test "the bridge's product conforms to the sync seam" do
    sync = Dexpace::AsyncTransport.sync_over(->(_r, _o, _c) {})

    assert(Dexpace::Transport.conforms?(sync))
  end

  test "the bridge is closeable, owns nothing, and leaves the wrapped transport usable" do
    sync = Dexpace::AsyncTransport.sync_over(FakeAsyncTransport.new(response: :ok))

    refute_predicate(sync, :owned?)
    assert_nil(sync.close)
    assert_predicate(sync, :closed?)
    assert_nil(sync.close)
    assert_equal(:ok, sync.call(:request, nil, nil))
  end

  # Two blocking calls arming the SAME token is the shape this bridge creates whenever a caller
  # derives one token per operation and issues two requests under it. A cancellation guard that is
  # per-token rather than per-registration arms only the first waiter, and the second blocks
  # forever -- a SEAM-18 violation that no single-waiter test can see. The join timeout is the
  # assertion: without it the suite hangs instead of failing.
  test "two concurrent waits on one token both unblock when it is cancelled" do
    source = Dexpace::Cancellation.source
    bridges = Array.new(2) do
      Dexpace::AsyncTransport.sync_over(
        ->(_r, _o, _c) { Dexpace::Async::Completer.new.future },
      )
    end
    reasons = ::Queue.new

    threads = bridges.map do |bridge|
      ::Thread.new do
        bridge.call(:request, nil, source.token)
      rescue Dexpace::CancelledError => error
        reasons << error.reason
      end
    end
    sleep(0.05)
    source.cancel(:stop)

    threads.each do |thread|
      assert(thread.join(5), "a waiter never unblocked: SEAM-18's interruption clause is violated")
    end
    seen = []
    seen << reasons.pop until reasons.empty?

    assert_equal(%i[stop stop], seen)
  end
end
