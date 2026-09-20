# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "vacuous"
require_relative "transport_case"

module Dexpace
  module Conformance
    # The thin RSpec driver (design §9.3). Never required by lib/dexpace/conformance.rb: an
    # RSpec-only consumer opts in with `require "dexpace/conformance/rspec_driver"`, exactly as it
    # opts into RSpec itself, so a Minitest-only consumer never loads a file naming the other
    # framework. `::RSpec` is resolved inside the method body, at call time, in the consumer's
    # process where the framework is already loaded; this file requires nothing of it (NFR-2).
    #
    # One example group per assertion with one example each, in the Minitest driver's shape: a
    # waived id and a Vacuous are skips naming why, a Failure propagates as the example's failure
    # carrying the expected and actual values, and the case is torn down in an ensure.
    module RSpecDriver
      # @param suite [#assertions] anything shaped like TransportSuite: an ordered #assertions
      # @param build [#call] the keyword-taking factory building the SDK-managed transport
      # @param borrow [#call, nil] the port-taking factory returning a BorrowedPair, or nil
      # @param waive [Array<String>] requirement IDs skipped and never run
      # @param settle [#call, nil] suite contract clause 8's send primitive; nil takes the default
      # @param around [#call, nil] clause 9's wrapper around each assertion's invocation
      # @param wire [#call, nil] clause 11's fixture factory; nil takes WireServer
      # @return [void]
      def self.conformance(suite, build:, borrow: nil, waive: [], settle: nil, around: nil,
                           wire: nil)
        rspec = ::Object.const_get(:RSpec) # resolved at call time, in the consumer's process
        suite.assertions.each do |assertion|
          group = rspec.describe(assertion.name)
          group.it("satisfies #{assertion.ids.join(", ")}") do
            RSpecDriver.drive(assertion, self, waive: waive, build: build, borrow: borrow,
                                               settle: settle, around: around, wire: wire,)
          end
        end
      end

      # One assertion in one fresh case, torn down whatever happened -- or a skip naming the
      # waived id, before any case is built. `example` is the example's own self, whose #skip a
      # waiver and a Vacuous both reach.
      #
      # @api private
      def self.drive(assertion, example, waive:, build:, borrow:, settle:, around:, wire:)
        waived = assertion.ids & waive
        return example.skip("waived: #{waived.join(", ")}") unless waived.empty?

        kase = TransportCase.new(
          build: build, borrow: borrow,
          settle: settle || TransportCase::DEFAULT_SETTLE, wire: wire || TransportCase::DEFAULT_WIRE,
        )
        begin
          around ? around.call { assertion.call(kase) } : assertion.call(kase)
        rescue Vacuous => error
          example.skip("vacuous: #{error.reason}")
        ensure
          kase.teardown
        end
      end
    end
  end
end
