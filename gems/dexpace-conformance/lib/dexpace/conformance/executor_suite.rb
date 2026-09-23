# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "executor_case"
require_relative "runner"
require_relative "executor_suite/lifecycle"
require_relative "executor_suite/shutdown"

module Dexpace
  module Conformance
    # Appendix B.7's lifecycle half, and the HARNESS half of SEAM-25's lifecycle event.
    #
    # **That reassignment is a CORRECTION to a committed record, stated as one.** Phase 2
    # postponed the event; 8b's design said "the HARNESS half -- the assertion living in
    # dexpace-conformance -- is 8a's, and 8b hands it the shape rather than writing it." 8a wrote
    # the protocol, the wire fixture and the transport suite, and wrote NO executor suite; 8b
    # supplied the shape and emits the event. So the harness half was unwritten after phase 8,
    # phase 9 writes it, and the earlier record is wrong about which phase delivers it.
    #
    # Two clauses are SCOPED OUT with reasons rather than silently dropped: ASYNC-15's clause (c),
    # interrupt-safety, needs a pending interrupt and §8.3 bans every primitive that could arrange
    # one; and SEAM-18 is the executor seam's SHAPE rather than an implementation property, which
    # 8b's own suite asserts.
    #
    # Every lifecycle observation here goes through `ExecutorCase#shutdowns`, the count of
    # `Events::INSTRUMENTATION_SHUTDOWN` payloads the case's own recorder saw. That is the only
    # channel a filed executor exposes a shutdown on; an assertion reading a `#shutdown_count`
    # would be reading a method no adapter in this repository defines.
    module ExecutorSuite
      extend self

      # What a green run of this suite does NOT prove.
      PREAMBLE = "dexpace-conformance executor suite: ASYNC-15's clause (c) and SEAM-18 are " \
                 "scoped out with their reasons and are NOT among the things a green run " \
                 "proves. Without `record_events: true` an UNLATCHED executor passes XCUT-13, " \
                 "because \"the shutdown ran twice\" is visible only in the lifecycle event. " \
                 "ASYNC-3 is an unsatisfied MUST (design §10.5): it fails against every executor " \
                 "this repository can build, and a first-party run waives it by ID."

      # @return [Array<Assertion>] the suite's assertions, frozen and ordered
      def assertions
        ASSERTIONS
      end

      # @param build [#call] keyword-taking executor factory; the suite passes `events:` when
      #   `record_events:` is true and nothing otherwise
      # @param borrow [#call, nil] pool -> a holder that borrows it, or nil
      # @param functional [#call, nil] a RESOURCE-FREE implementation for ASYNC-17, or nil
      # @param record_events [Boolean] whether `build:` accepts an `events:` sink
      # @param waive [Array<String>] requirement IDs recorded :waived without running
      # @param around [#call, nil] the suite contract's clause 9 wrapper
      # @param accepted_vacuous [Hash{String => String}] sanctioned MUST-level vacuities
      # @param would_fail [Array<String>] waived IDs whose assertion would have failed
      # @return [Report]
      def run(build:, borrow: nil, functional: nil, record_events: false, waive: [], around: nil,
              accepted_vacuous: {}, would_fail: [])
        Runner.run(assertions, waive: waive, around: around, preamble: PREAMBLE,
                               accepted_vacuous: accepted_vacuous, would_fail: would_fail,) do
          ExecutorCase.new(build: build, borrow: borrow, functional: functional,
                           record_events: record_events,)
        end
      end

      # The two groups, each a private module of its own file.
      ASSERTIONS = (Lifecycle::ASSERTIONS + Shutdown::ASSERTIONS).freeze
      private_constant :ASSERTIONS
    end
  end
end
