# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "completer"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../error/seam_error"

module Dexpace
  # The async layer's namespace, reopened here to carry CFG-18's delay beside phase 2's pivot.
  module Async
    # The void value CFG-18's future settles with. Not nil: SEAM-16 makes Async::Settlement refuse
    # a nil response ("MUST NOT complete successfully with a null/absent value", structural), so
    # "completing with an empty/void value" is spelled `true` here.
    ELAPSED = true
    private_constant :ELAPSED

    # CFG-18's scheduled non-blocking delay: a Future that completes with the void value after
    # `duration` seconds elapse on the registered Fiber.scheduler, WITHOUT blocking a thread.
    #
    # Scheduler-conditional, and it raises rather than degrades (P5-9). Under a registered
    # scheduler Thread::Queue#pop(timeout:) routes through the scheduler's block/unblock hooks and
    # unmounts the fiber -- verified on 3.2.11, 3.4.10 and 4.0.6: the pop calls #block exactly
    # once and #kernel_sleep never -- so the carrier thread is free. With no scheduler there is no
    # non-blocking path at all: a thread-backed delay would satisfy the three MUST clauses while
    # violating the SHOULD's headline, so a positive duration raises Dexpace::SeamError naming
    # Fiber.set_scheduler and the blocking alternative, Dexpace::Clock#sleep. SeamError is phase
    # 2's "a seam in a state the caller must fix but did not pass in" -- a process-level facility
    # the caller installs and did not, with a correct argument -- and not a claim that the
    # scheduler is one of SEAM-2's five seams.
    #
    # It lives here and not as a fourth method on Clock (P5-10): CFG-15's seam exposes three
    # operations and a fake owes it exactly those, while CFG-18 names "the async layer" as its
    # subject. And it takes no clock: keyword, because nothing in its four branches reads a clock
    # -- the wait is the queue's own timeout, a duration and not an instant, and no fake clock can
    # make a real queue wake early.
    #
    # @param duration [Numeric] seconds; zero completes the future at once
    # @return [Dexpace::Async::Future] completing with the void value `true`
    # @raise [Dexpace::InvalidArgumentError] on a negative or non-numeric duration, before
    #   anything is scheduled
    # @raise [Dexpace::SeamError] on a positive duration with no Fiber.scheduler registered
    def self.delay(duration)
      seconds = validate_delay(duration)
      completer = Completer.new
      if seconds.zero?
        completer.fulfil(ELAPSED)
        return completer.future
      end
      raise SeamError, NO_SCHEDULER if ::Fiber.scheduler.nil?

      queue = ::Thread::Queue.new
      # CFG-18's fourth clause: cancelling the future cancels the scheduled task so the scheduler
      # thread is not held. Completer#on_cancel fires on Future#cancel -> Completer#request_cancel,
      # and the completer drops its hook list on settle, so there is nothing to detach.
      completer.on_cancel { queue.push(:cancel) }
      ::Fiber.schedule do
        # nil means the duration elapsed and :cancel means the future was cancelled. Sound only
        # because this queue is per-call, private and never closed -- a closed queue pops nil too.
        completer.fulfil(ELAPSED) unless queue.pop(timeout: seconds) == :cancel
      end
      completer.future
    end

    NO_SCHEDULER = "Async.delay needs a registered Fiber.scheduler to complete without blocking " \
                   "a thread (CFG-18). Register one with Fiber.set_scheduler, or use " \
                   "Dexpace::Clock#sleep, which blocks the calling thread by design."
    private_constant :NO_SCHEDULER

    # @return [Float] the duration as seconds
    def self.validate_delay(duration)
      Model.required!("duration", duration)
      unless duration.is_a?(::Numeric)
        raise InvalidArgumentError, "duration must be a number of seconds, got #{duration.class}"
      end
      if duration.negative?
        raise InvalidArgumentError, "duration must be non-negative, got #{duration}"
      end

      seconds = duration #: untyped
      seconds.to_f
    end
    private_class_method :validate_delay
  end
end
