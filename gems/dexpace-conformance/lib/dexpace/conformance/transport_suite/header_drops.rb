# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "../vacuous"
require_relative "../failure"
require_relative "../scripts"
require_relative "checks"

module Dexpace
  module Conformance
    module TransportSuite
      # Group 7, phase 8c's header-drop rows: TRANSPORT-12 and TRANSPORT-13. Written against
      # `kase.settle`, `kase.wire` and the `build:` factory's `logger:` setting -- the two
      # settings the suite contract's clause 4 allows -- and nothing else. Both resolve vacuous BY
      # MEASUREMENT on an adapter whose native client accepts every model-valid name: the bad name
      # is sent and the wire is read, which is what the first-party sync adapter's driver reports,
      # and why neither row could be a shared assertion declaring itself vacuous (8a's R16). A
      # private_constant of TransportSuite.
      module HeaderDrops
        extend self

        # A model-valid header name the RFC 7230 token grammar refuses: HTTP-17 admits `:`.
        NON_TOKEN = "X-Bad:Name"

        # How many distinct non-token names TRANSPORT-13's bound is probed with; a policy that
        # warns for every one of them is unbounded.
        DISTINCT_NAMES = 200

        # TRANSPORT-12's clause: "send a model-valid non-token header name plus a normal header;
        # assert send does not throw, the bad header is absent, the normal header present". The
        # antecedent is measured: an adapter whose native client accepted the name -- it reached
        # the wire beside the normal one and the send succeeded -- has no drop to make.
        #
        # @param kase [TransportCase]
        # @return [nil]
        # @raise [Vacuous] when the native client accepted the model-valid name
        def non_token_name_is_dropped_and_the_rest_dispatched(kase)
          kase.wire(script: Scripts.fixed("ok"))
          request = kase.request(headers: Checks.headers(NON_TOKEN => "v", "X-Normal" => "n"))
          error = Checks.error_from { kase.settle(kase.transport, request).close }

          Checks.check(error.nil?, "the native exception escaped the send contract",
                       ids: ["TRANSPORT-12"], expected: "a normal completion",
                       actual: error&.class,)
          sent = Checks.last_request(kase, ids: ["TRANSPORT-12"])
          Checks.expect(sent.header("x-normal"), "n", "the normal header did not dispatch",
                        ids: ["TRANSPORT-12"],)
          vacuous_unless_absent!(sent)
        end

        # TRANSPORT-13's clause: "under once-per-header assert the same name warns once then goes
        # quiet, a different name warns once" -- read off the transport's own logger, which the
        # `build:` factory takes -- and the bound: two hundred distinct names in one request warn
        # fewer than two hundred times.
        #
        # @param kase [TransportCase]
        # @return [nil]
        # @raise [Vacuous] when the native client accepted the model-valid name
        def header_drops_are_logged_once_per_name_and_bounded(kase)
          kase.wire(script: Scripts.fixed("ok"))
          sink = RecordingSink.new
          transport = kase.transport(logger: Dexpace::Instrumentation::Logger.build(sink: sink))
          first = Checks.headers(NON_TOKEN => "v")
          second = Checks.headers("Y-Bad:Name" => "v")
          [first, first, second].each do |headers|
            kase.settle(transport, kase.request(headers: headers)).close
          end
          vacuous_unless_dropped!(kase, sink)

          Checks.expect(sink.severities, %i[warn debug warn],
                        "the once-per-name policy did not warn once then go quiet",
                        ids: ["TRANSPORT-13"],)
          check_bounded(kase, transport, sink)
        end

        # The registry's rows, `[ids, name, function]`, in the group's order.
        ROWS = [
          ["TRANSPORT-12", "a model-valid non-token header name is dropped and the rest still " \
                           "dispatches", :non_token_name_is_dropped_and_the_rest_dispatched,],
          ["TRANSPORT-13", "header drops are logged once per name, then quietly, and the latch " \
                           "is bounded", :header_drops_are_logged_once_per_name_and_bounded,],
        ].freeze
        private_constant :ROWS

        # The registry, built from ROWS.
        ASSERTIONS = Checks.registry(self, ROWS)

        # Dexpace::Instrumentation's duck-typed sink, recording the severity and payload of every
        # drop record so an assertion can read them back; every other record is ignored.
        class RecordingSink
          def initialize
            @records = [] #: Array[[Symbol, untyped]]
            @mutex = ::Thread::Mutex.new
          end

          # The sink's four writers, each recording under its own severity.
          def debug(message = nil, &) = record(:debug, message, &)
          # (see #debug)
          def info(message = nil, &) = record(:info, message, &)
          # (see #debug)
          def warn(message = nil, &) = record(:warn, message, &)
          # (see #debug)
          def error(message = nil, &) = record(:error, message, &)
          # The four predicates: every severity is enabled, so the policy's choice is what shows.
          def debug? = true
          def info? = true
          def warn? = true
          def error? = true

          # The severities of every drop record, in order.
          def severities
            @mutex.synchronize { @records.map(&:first) }
          end

          private

          def record(severity, message)
            payload = block_given? ? yield : message
            event = payload.is_a?(::Hash) ? payload["event"] : nil
            return nil unless event == Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED

            @mutex.synchronize { @records << [severity, payload] }
            nil
          end
        end
        private_constant :RecordingSink

        private

        def vacuous_unless_absent!(sent)
          return if sent.header(NON_TOKEN.downcase).nil?

          raise Vacuous, "the native client accepted the model-valid name #{NON_TOKEN} and sent " \
                         "it, so it rejects no header the SDK model admits (TRANSPORT-12's " \
                         "antecedent is absent)"
        end

        def vacuous_unless_dropped!(kase, sink)
          return unless sink.severities.empty?

          sent = Checks.last_request(kase, ids: ["TRANSPORT-13"])
          if sent.header("y-bad:name").nil?
            raise Failure.new("a non-token name was dropped without a drop record",
                              expected: "a TRANSPORT_HEADER_DROPPED record per drop",
                              actual: "none", requirement_ids: ["TRANSPORT-13"],)
          end

          raise Vacuous, "the native client accepted the model-valid names and sent them, so " \
                         "there is no drop to log (TRANSPORT-13's antecedent is absent)"
        end

        def check_bounded(kase, transport, sink)
          many = Checks.headers(Array.new(DISTINCT_NAMES) { |i| ["Z-Bad:#{i}", "v"] }.to_h)
          before = sink.severities.size
          kase.settle(transport, kase.request(headers: many)).close
          warned = sink.severities.drop(before).count(:warn)

          Checks.check(warned < DISTINCT_NAMES, "the once-per-name latch grew without bound",
                       ids: ["TRANSPORT-13"], expected: "fewer than #{DISTINCT_NAMES} warnings",
                       actual: warned,)
        end
      end
      private_constant :HeaderDrops
    end
  end
end
