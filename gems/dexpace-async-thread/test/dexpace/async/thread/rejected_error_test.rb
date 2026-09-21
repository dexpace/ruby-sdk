# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/async/thread"

# ASYNC-2's companion: a full queue is backpressure to retry or shed, a closed pool
# (Dexpace::ClosedError, phase 2's) is a lifecycle bug -- two classes because a caller's two
# sensible responses differ.
class RejectedErrorTest < DexpaceTestCase
  test "is a StandardError that Dexpace::Error catches, and is not a transport failure" do
    error = Dexpace::Async::Thread::RejectedError.new("dexpace-async-thread: queue full")

    assert_kind_of(::StandardError, error)
    assert_kind_of(Dexpace::Error, error)
    refute_kind_of(::IOError, error)
    refute_kind_of(Dexpace::ClosedError, error)
  end

  test "rescue Dexpace::Error matches it through the module root" do
    caught = begin
      raise Dexpace::Async::Thread::RejectedError, "full"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::Async::Thread::RejectedError, caught)
  end

  # The #retryable? protocol is Dexpace::TransportError's (phase 8a) and a pool rejection never
  # crosses a retry boundary: it happens at the bridge, above the pipeline.
  test "answers no #retryable? predicate" do
    error = Dexpace::Async::Thread::RejectedError.new("full")

    refute_respond_to(error, :retryable?)
    refute(Dexpace::Resilience::Policy.throwable_retryable?(error))
  end
end
