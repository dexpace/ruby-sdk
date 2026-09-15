# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# Design §9 Addendum A1 and verified fact 2. dexpace-async-thread defines Dexpace::Async::Thread,
# after which a bare `Thread` written inside module Dexpace::Async resolves to that module rather
# than to Ruby's class -- and dexpace-core's own suite never requires that gem, so this is the only
# place core can catch it. Task 3's cop is the other half: the cop catches it on a file nobody ran,
# this catches it on a file nobody linted.
#
# This test defines a constant that outlives it. It is in its own file, and it is the last word on
# the subject: nothing else in the suite may assume Dexpace::Async::Thread is undefined.
class DexpaceAsyncFutureShadowingTest < DexpaceTestCase
  def stand_in!
    return if Dexpace::Async.const_defined?(:Thread, false)

    Dexpace::Async.const_set(:Thread, Module.new)
  end

  test "the pivot still works once the adapter gem's namespace exists" do
    stand_in!

    completer = Dexpace::Async::Completer.new
    response = Object.new
    producer = ::Thread.new { completer.fulfil(response) }

    assert_same(response, completer.future.value)

    producer.join

    assert_instance_of(Module, Dexpace::Async::Thread,
                       "the stand-in is still a bare Module, so the pivot did not reach Ruby's " \
                       "Thread by accident",)
  end

  # Every ::-qualified constant the pivot reaches, exercised once each with the stand-in present:
  # Mutex (the completer's), Queue (the gate) and the cancellation guard's Mutex.
  test "cancellation through a composed token still works under the stand-in" do
    stand_in!
    completer = Dexpace::Async::Completer.new
    source = Dexpace::Cancellation.source
    token = Dexpace::Cancellation.any(source.token, Dexpace::Cancellation.source.token)
    canceller = ::Thread.new do
      sleep(0.02)
      source.cancel(:stop)
    end

    error = assert_raises(Dexpace::CancelledError) { completer.future.value(cancellation: token) }

    assert_equal(:stop, error.reason)
    canceller.join
  end
end
