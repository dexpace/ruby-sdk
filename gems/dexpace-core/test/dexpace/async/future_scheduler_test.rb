# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/probe_scheduler"
require "dexpace"

# SEAM-17. Design §3.3 claims the pivot is scheduler-transparent -- that a caller inside Async { }
# awaits it without blocking the reactor. That claim rests on one Ruby fact: a blocking
# Thread::Queue pop routes through a registered Fiber.scheduler's block/unblock hooks instead of
# parking the OS thread. This asserts the fact rather than restating the claim, and it runs on
# every row of the CI matrix, which is what makes it a standing check.
class DexpaceAsyncFutureSchedulerTest < DexpaceTestCase
  test "value blocks through the scheduler, not the thread" do
    scheduler = ProbeScheduler.new
    completer = Dexpace::Async::Completer.new
    delivered = []

    Fiber.set_scheduler(scheduler)
    begin
      Fiber.schedule { delivered << completer.future.value }
      Fiber.schedule { completer.fulfil(:response) }
    ensure
      Fiber.set_scheduler(nil)
    end

    assert_equal([:response], delivered)
    assert_includes(scheduler.hooks, [:block, "Thread::Queue"])
    assert_includes(scheduler.hooks, [:unblock, "Thread::Queue"])
  end

  # The registry's single-flight gate is the same Thread::Queue wait, so a second resolver inside
  # a scheduler parks on the scheduler too rather than on the OS thread.
  test "a settled future never touches the scheduler at all" do
    scheduler = ProbeScheduler.new
    completer = Dexpace::Async::Completer.new
    completer.fulfil(:response)
    delivered = []

    Fiber.set_scheduler(scheduler)
    begin
      Fiber.schedule { delivered << completer.future.value }
    ensure
      Fiber.set_scheduler(nil)
    end

    assert_equal([:response], delivered)
    assert_empty(scheduler.hooks)
  end
end
