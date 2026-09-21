# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "failure"
require_relative "vacuous"
require_relative "transport_case"

module Dexpace
  module Conformance
    # The thin Minitest driver (design §9.3): `extend` it into a test class and call
    # `conformance(suite, build:)`, and one test method per assertion is defined. Each generated
    # test runs its OWN assertion directly, in a fresh TransportCase built from the same settings
    # every other assertion gets -- so a Minitest `-n` filter exercises exactly the code path a
    # full run does, never a replay of a cached Result -- and tears the case down in an ensure. A
    # Vacuous is reported as a skip naming the reason, a Failure as a flunk naming the ids, and a
    # waived id as a skip naming it, which is design §9.3's "the gap stays visible" in Minitest's
    # own summary; anything else propagates as an error and is never silently a failure.
    #
    # Named MinitestDriver and not Minitest: inside module Dexpace::Conformance a constant named
    # Minitest would shadow ::Minitest for every bare reference in the namespace, this file's
    # included (5a's P5-3 reasoning, applied a second time). Nothing here requires or names the
    # framework: `skip` and `flunk` are sent to the test instance the consumer's class already is,
    # so this gem stays at `dexpace-core` and nothing else (NFR-2) and a Minitest that is a bundled
    # gem (verified fact 17) is never a runtime constraint on a consumer.
    #
    # The consumer's test class should inherit the repository's own base where it has one -- the
    # first-party driver inherits DexpaceTestCase, whose teardown counts threads, so a leaked
    # fixture thread fails the generated test that leaked it.
    module MinitestDriver
      # @param suite [#assertions] anything shaped like TransportSuite: an ordered #assertions
      # @param build [#call] the keyword-taking factory building the SDK-managed transport
      # @param borrow [#call, nil] the port-taking factory returning a BorrowedPair, or nil
      # @param waive [Array<String>] requirement IDs recorded as skipped and never run
      # @param settle [#call, nil] suite contract clause 8's send primitive; nil takes the default
      # @param around [#call, nil] clause 9's wrapper around each assertion's invocation
      # @param wire [#call, nil] clause 11's fixture factory; nil takes WireServer
      # @return [void]
      def conformance(suite, build:, borrow: nil, waive: [], settle: nil, around: nil, wire: nil)
        case_options = { build: build, borrow: borrow, settle: settle || TransportCase::DEFAULT_SETTLE,
                         wire: wire || TransportCase::DEFAULT_WIRE, }.freeze
        suite.assertions.each do |assertion|
          define_method(MinitestDriver.method_name_for(assertion)) do
            MinitestDriver.drive(self, assertion, around, case_options, waive: waive)
          end
        end
      end

      # The generated method's name: `test_` plus the assertion's name with every non-word run
      # collapsed to one underscore, so `-n` can select it and Minitest's naming rule holds.
      #
      # @param assertion [Assertion]
      # @return [String]
      def self.method_name_for(assertion)
        "test_#{assertion.name.gsub(/\W+/, "_").gsub(/\A_|_\z/, "")}"
      end

      # One assertion in one fresh case on the given test instance, torn down whatever happened
      # -- or a skip naming the waived id, before any case is built. Clause 9: the driver INVOKES
      # the assertion, so it may wrap it -- how an async driver opens the reactor the assertion's
      # body reads a streamed response inside.
      #
      # @api private
      def self.drive(test, assertion, around, case_options, waive:)
        waived = assertion.ids & waive
        return test.skip("waived: #{waived.join(", ")}") unless waived.empty?

        kase = build_case(case_options)
        around ? around.call { assertion.call(kase) } : assertion.call(kase)
      rescue Vacuous => error
        test.skip("vacuous: #{error.reason}")
      rescue Failure => error
        test.flunk("#{assertion.ids.join(", ")}: #{error.message}")
      ensure
        kase&.teardown
      end

      # The fresh case each generated test builds from the driver's frozen options.
      #
      # @api private
      # @return [TransportCase]
      def self.build_case(case_options)
        TransportCase.new(build: case_options.fetch(:build), borrow: case_options[:borrow],
                          settle: case_options.fetch(:settle), wire: case_options.fetch(:wire),)
      end
    end
  end
end
