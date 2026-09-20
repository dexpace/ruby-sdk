# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "failure"
require_relative "vacuous"
require_relative "assertion"
require_relative "result"
require_relative "report"
require_relative "transport_case"
require_relative "transport_suite/checks"
require_relative "transport_suite/outbound"
require_relative "transport_suite/inbound"
require_relative "transport_suite/streaming"
require_relative "transport_suite/resilience"
require_relative "transport_suite/lifecycle"

module Dexpace
  module Conformance
    # The transport suite's runner (8a's R7, R16): every assertion runs in a FRESH TransportCase,
    # its raise is mapped onto one of Result's five statuses -- Vacuous to :vacuous, Failure to
    # :failed, anything else to :error and never silently a failure -- the case is torn down in an
    # ensure whatever happened, and an assertion whose ids meet the waiver list is recorded
    # :waived without its body ever running. A module with `extend self` (the repository's rule
    # for a function module), so the two functions are instance rows in the surface manifest.
    module TransportSuite
      extend self

      # P8-9, printed at the head of every report: what a green run of this suite does NOT prove,
      # so a third-party adapter author whose adapter passes is not misled about TLS verification
      # or connect-timeout classification, which live in the adapter's own suite.
      PREAMBLE = "dexpace-conformance transport suite: the wire fixture speaks plaintext only " \
                 "and exercises no connect timeout, so TLS verification and TRANSPORT-4's " \
                 "open-timeout classification are NOT among the things a green run proves " \
                 "(P8-9); assert both in the adapter's own suite."

      # The suite's assertions, frozen and ordered: the five groups this phase ships, concatenated.
      #
      # @return [Array<Assertion>]
      def assertions
        ASSERTIONS
      end

      # Runs the suite against one adapter.
      #
      # @param build [#call] keyword-taking factory building the SDK-managed transport; the suite
      #   passes at most `timeout:` and `logger:`
      # @param borrow [#call, nil] a one-argument factory taking the fixture's port and returning
      #   a BorrowedPair, or nil when the adapter has no borrowing construction
      # @param waive [Array<String>] requirement IDs whose assertions are recorded :waived and not
      #   run -- a gap the port has named, printed on every run (design §9.3)
      # @param around [#call, nil] clause 9: a callable handed each assertion's invocation as a
      #   block, so an async driver can wrap it in its reactor; nil invokes the assertion directly
      # @param settle [#call, nil] clause 8's send primitive; nil takes TransportCase's default
      # @param wire [#call, nil] clause 11's fixture factory; nil takes WireServer
      # @param assertions [Array<Assertion>] the assertions to run, the suite's own by default --
      #   a keyword so the suite's own tests hand in three of theirs without stubbing anything
      # @return [Report]
      def run(build:, borrow: nil, waive: [], around: nil, settle: nil, wire: nil,
              assertions: self.assertions)
        results = assertions.map do |assertion|
          if assertion.ids.intersect?(waive)
            Result.build(assertion: assertion, status: :waived)
          else
            run_one(assertion, build: build, borrow: borrow, around: around, settle: settle,
                               wire: wire,)
          end
        end
        Report.new(results, preamble: PREAMBLE)
      end

      private

      def run_one(assertion, build:, borrow:, around:, settle:, wire:)
        kase = TransportCase.new(
          build: build, borrow: borrow,
          settle: settle || TransportCase::DEFAULT_SETTLE, wire: wire || TransportCase::DEFAULT_WIRE,
        )
        begin
          # Clause 9: the runner INVOKES the assertion, so `around` can put a block around the
          # whole of it -- the reactor an async driver opens here is the one the body reads a
          # streamed response inside.
          around ? around.call { assertion.call(kase) } : assertion.call(kase)
          Result.build(assertion: assertion, status: :passed)
        rescue Vacuous => error
          Result.build(assertion: assertion, status: :vacuous, detail: error.reason)
        rescue Failure => error
          Result.build(assertion: assertion, status: :failed, detail: error.message)
        rescue ::StandardError => error
          Result.build(assertion: assertion, status: :error,
                       detail: "#{error.class}: #{error.message}",)
        ensure
          kase.teardown
        end
      end

      # The five groups, each a private module of its own file (one constant per file, and each
      # under RuboCop's module-length cap), concatenated in the order a reader meets the chapter:
      # outbound, inbound, streaming, resilience, lifecycle.
      ASSERTIONS = (Outbound::ASSERTIONS + Inbound::ASSERTIONS + Streaming::ASSERTIONS +
                    Resilience::ASSERTIONS + Lifecycle::ASSERTIONS).freeze
      private_constant :ASSERTIONS
    end
  end
end
