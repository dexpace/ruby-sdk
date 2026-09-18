# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "recovery_fixtures"
require_relative "fake_clock"
require_relative "fake_body"

# The fixtures phase 6a's retry suites fold over: a request per method, a response over a REAL
# ResponseBody (so `response.body.closed?` is the RETRY-35 assertion -- Dexpace::Response has no
# #closed? of its own), a retryable throwable that answers XCUT-6's capability and nothing else,
# and a step that hands a RetryStep a RECORDING cursor over the real one the driver minted, so
# the fork-for-every-drive rule is asserted against the real runtime rather than a stand-in
# (5b's checklist item 12's route). Built on RecoveryFixtures rather than beside it.
module RetryFixtures
  include RecoveryFixtures

  # A throwable that is retryable by capability -- an IOError, as a socket read timeout would
  # be (RETRY-24's shape) -- and one that answers the capability with false.
  class RetryableError < ::IOError
    def retryable? = true
  end

  # The other answer: an IOError that says no, which a type match would call retryable.
  class UnretryableError < ::IOError
    def retryable? = false
  end

  # RETRY-25's discriminating fixture: a fatal-family error that ANSWERS the capability. A driver
  # that classified it would retry it; the correct driver never asks, because the fatal family
  # passes through an absent rescue arm before any classification runs.
  class RetryableFatal < ::NoMemoryError
    def retryable? = true
  end

  # Forwards everything to the real cursor and counts what the step did with it. #call raises
  # rather than counting: a pillar step that calls its own cursor is the defect the count exists
  # to find, and a raise names it at the site.
  class RecordingCursor
    attr_reader :forks, :calls, :real

    def initialize(real)
      @real = real
      @forks = 0
      @calls = 0
    end

    def fork(state: nil)
      @forks += 1
      @real.fork(state: state)
    end

    def call(request = @real.request)
      @calls += 1
      @real.call(request)
    end

    def request = @real.request
    def options = @real.options
    def cancellation = @real.cancellation
    def bundle = @real.bundle
    def spent? = @real.spent?
    def may_fork? = @real.may_fork?
    def state(stage) = @real.state(stage)
  end

  # A step that wraps the cursor before handing it on, for #forks and #calls.
  class RecordingWrapper
    attr_reader :cursors

    def initialize(step)
      @step = step
      @cursors = []
    end

    def stage = @step.stage

    def call(request, cursor)
      recording = RecordingCursor.new(cursor)
      @cursors << recording
      @step.call(request, recording)
    end
  end

  def retry_request(method: "GET", body: nil, url: "https://example.test/api")
    Dexpace::Request.build(method: Dexpace::Method.of(method), url: url,
                           headers: Dexpace::Headers::EMPTY, body: body,)
  end

  # A response over a closable single-use body, with optional inbound headers.
  def retry_response(code, headers: {}, request: retry_request)
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = code
    builder.body = response_body("body #{code}")
    unless headers.empty?
      inbound = Dexpace::Headers.inbound_builder
      headers.each { |name, value| inbound.add(name, value) }
      builder.headers = inbound.build
    end
    builder.build
  end

  def replayable_body = FakeBody.new("payload", replayable: true)
  def consumed_body = FakeBody.new("payload", replayable: false)

  # Settings over a FakeClock with a flat, jitter-free schedule unless told otherwise.
  def retry_settings(clock: FakeClock.new, **overrides)
    Dexpace::Resilience::RetrySettings.build(
      initial_delay: 0.1, multiplier: 2.0, max_delay: 8.0, jitter: 0.0,
      clock: clock, **overrides,
    )
  end
end
