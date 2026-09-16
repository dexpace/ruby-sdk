# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "response"
require_relative "../error/invalid_argument_error"

module Dexpace
  # HTTP-44 and HTTP-45's lazy typed-response wrapper. Design §7.3 names it flat.
  #
  # The handler is ANY object responding to #call(response) -- Dexpace::_ResponseHandler in sig/, a
  # lambda in a test (R7). Not the SEAM-22 witness: a witness responds to .dexpace_load(parsed,
  # ctx) and takes an ALREADY-PARSED value, so something must read the body, choose a codec and
  # parse before it runs, and `serde/4b78c08d` requires that something to be STATUS-AWARE. So the
  # handler needs the whole response, and the witness sits inside it -- which is what lets phase 7
  # supply a handler INTO this rather than replace it. Phase 3b builds no witness, no codec and no
  # status-aware handler.
  class TypedResponse
    def initialize(response:, handler:)
      unless response.is_a?(Dexpace::Response)
        raise Dexpace::InvalidArgumentError,
              "response must be a Dexpace::Response, got #{response.class}"
      end
      unless handler.respond_to?(:call)
        raise Dexpace::InvalidArgumentError,
              "handler must respond to #call(response), got #{handler.class}"
      end

      @response = response
      @handler = handler
      @state = :unstarted
      @value = nil
      @error = nil
      @mutex = ::Thread::Mutex.new
      @condition = ::Thread::ConditionVariable.new
    end

    # The wrapped response, exposed so a caller can reach anything the five raw accessors do not
    # name without going through #value.
    attr_reader :response

    # HTTP-44's raw accessors: status, headers, protocol, reason and request WITHOUT consuming the
    # body. They take no lock, which is not an optimisation -- a lock here would block a caller
    # reading a status while another fiber of the same thread sits inside the parse.
    def status = @response.status
    # The raw headers, unlocked, for the reason above.
    def headers = @response.headers
    # The raw protocol, unlocked, for the reason above.
    def protocol = @response.protocol
    # The raw reason phrase, unlocked, for the reason above.
    def reason = @response.reason
    # The originating request, unlocked, for the reason above.
    def request = @response.request

    # HTTP-44: parse at most once on first access and memoise the OUTCOME. The state machine is
    # explicit -- :unstarted, :running, :done, :failed -- and never inferred from @value being
    # nil, because `@value ||= handler.call(response)` re-runs the handler for one that legitimately
    # decodes to nil, and the second run reads a single-use body that is already gone. Both a nil
    # success and a raised failure are memoised.
    #
    # A memoised failure is re-raised with a bare `raise`, which returns THE SAME OBJECT with its
    # #cause and its original backtrace intact (verified on 3.2.11, 3.4.10 and 4.0.6) -- no
    # #exception dance and no backtrace juggling.
    #
    # HTTP-45: the mutex is held across the state flip and across NOTHING else, never across the
    # parse, with a caller arriving mid-parse waiting on a Thread::ConditionVariable over the same
    # mutex. Ruby's Mutex and ConditionVariable both defer to an INSTALLED Fiber scheduler, which
    # is HTTP-45's "does not pin the carrier thread" in Ruby's vocabulary -- and the qualifier is
    # load-bearing (P3-27). With no scheduler installed, which is the default, a second FIBER of
    # the same thread arriving mid-parse blocks the carrier thread inside #wait; if the parsing
    # fiber is never resumed the process aborts with "No live threads left. Deadlock?". Verified on
    # 3.2.11, 3.4.10 and 4.0.6. Two threads are unaffected, and so is a second fiber arriving after
    # the parse has settled -- both are tested. It is the same shape as the three unsatisfied MUSTs
    # design §10.5 splits, and it is recorded rather than papered over.
    def value
      run_handler if claim_parse
      settled = @mutex.synchronize { [@state, @value, @error] }
      raise settled[2] if settled[0] == :failed

      settled[1]
    end

    private

    def claim_parse
      @mutex.synchronize do
        @condition.wait(@mutex) while @state == :running
        if @state == :unstarted
          @state = :running
          true
        else
          false
        end
      end
    end

    def run_handler
      settle(:done, @handler.call(@response), nil)
    rescue ::StandardError => error
      settle(:failed, nil, error)
    rescue ::Exception => error # rubocop:disable Lint/RescueException -- re-raised below, unchanged; see the comment
      # A handler that raises OUTSIDE StandardError -- NoMemoryError, a SignalException, a
      # ScriptError out of a broken handler -- would otherwise unwind past the rescue above and
      # leave the state :running, with every other caller waiting on the condition variable for
      # the life of the process, which is the one failure mode worse than a raised error. The
      # failure is memoised and re-raised UNCHANGED, so nothing is swallowed and a signal still
      # lands. ResponseLoggingBody#ensure_drained flips its state in an ensure for the same reason.
      settle(:failed, nil, error)
      raise
    end

    def settle(state, value, error)
      @mutex.synchronize do
        if @state == :running
          @value = value
          @error = error
          @state = state
          @condition.broadcast
        end
      end
      nil
    end
  end
end
