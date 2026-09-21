# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "../scripts"
require_relative "checks"

module Dexpace
  module Conformance
    module TransportSuite
      # Group 5, lifecycle, concurrency and the cross-phase test: TRANSPORT-5, TRANSPORT-6,
      # TRANSPORT-15, TRANSPORT-16, TRANSPORT-29 and phase 7c's PAGE-36. TRANSPORT-12 and
      # TRANSPORT-13 are NOT here: both are phase 8c's rows, whose antecedent -- a native wire
      # grammar stricter than the SDK model's -- the first-party sync adapter measures absent in
      # its own suite; a shared assertion declaring them vacuous would be an adapter-specific
      # claim in a portable suite (8a's R16), so 8c adds their assertions with its driver. A
      # private_constant of TransportSuite.
      module Lifecycle
        extend self

        # TRANSPORT-5's two per-call budgets, and the bounds each call's elapsed time must sit in.
        BUDGETS = { 0.2 => (0.15..0.7), 1.0 => (0.9..2.0) }.freeze

        # TRANSPORT-5's clause: "two concurrent calls with different per-call timeouts; assert each
        # is bounded by its own value" -- against a server that never answers, each call raises
        # after its own budget and neither waits for the other's.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def concurrent_per_call_timeouts_bound_their_own_calls(kase)
          kase.wire(script: Scripts.hang_before_headers)
          transport = kase.transport
          request = kase.request
          timings = BUDGETS.keys.map do |seconds|
            ::Thread.new { timed_settle(kase, transport, request, seconds) }
          end.map(&:value)

          Checks.check(Checks.within_bands?(timings, BUDGETS.values),
                       "per-call timeouts did not bound their own calls independently",
                       ids: ["TRANSPORT-5"], expected: BUDGETS.values, actual: timings,)
        end

        # TRANSPORT-6, asserted by its observable outcome rather than by its antecedent: a per-call
        # timeout small enough to truncate to zero on a coarser native API must still bound the
        # call -- it never becomes "no timeout". A hanging server and a bound of two seconds.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def a_near_zero_timeout_never_becomes_unbounded(kase)
          kase.wire(script: Scripts.hang_before_headers)
          error, took = Checks.timed_error do
            kase.settle(kase.transport, kase.request, Checks.options(timeout: 0.000001))
          end

          bounded = Checks.retryable_failure?(error) && took < 2.0
          Checks.check(bounded, "a near-zero timeout did not bound the call",
                       ids: ["TRANSPORT-6"], expected: "a retryable failure in under two seconds",
                       actual: [error&.class, took],)
        end

        # TRANSPORT-15's borrowed half (suite contract 4a): a transport over the caller's own
        # client is closed, and the caller's client is still usable afterwards, by the adapter's
        # own probe.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def borrowed_client_survives_the_transports_close(kase)
          kase.wire(script: Scripts.fixed("ok"))
          pair = kase.borrowed_transport
          kase.settle(pair.transport, kase.request).close
          pair.transport.close

          Checks.expect([pair.transport.closed?, pair.transport.owned?, pair.still_usable?],
                        [true, false, true],
                        "the borrowed client did not survive the transport's close as usable",
                        ids: ["TRANSPORT-15"],)
        end

        # TRANSPORT-15's owned half and TRANSPORT-16: an owning transport closed twice is stable,
        # reports closed, and refuses a later send with Dexpace::ClosedError (SEAM-15).
        #
        # @param kase [TransportCase]
        # @return [nil]
        def owned_transport_refuses_a_send_after_close(kase)
          kase.wire(script: Scripts.fixed("ok"))
          transport = kase.transport
          transport.close
          transport.close
          error = Checks.error_from { kase.settle(transport, kase.request) }

          Checks.expect([transport.closed?, transport.owned?, error.class],
                        [true, true, Dexpace::ClosedError],
                        "a send after close on an owning transport did not raise ClosedError",
                        ids: %w[TRANSPORT-15 TRANSPORT-16],)
        end

        # TRANSPORT-29's clause: "fire many concurrent calls through one transport and assert each
        # response matches its own request" -- the assertion that fails against a shared native
        # client (8a's verified fact 9) and passes against a per-call or serialised one.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def concurrent_calls_each_get_their_own_response(kase)
          kase.wire(script: Scripts.echo_path)
          transport = kase.transport
          mismatches = ::Thread::Queue.new
          Array.new(8) do |thread_index|
            ::Thread.new { echo_round_trips(kase, transport, thread_index, mismatches) }
          end.each(&:join)
          found = [] #: Array[untyped]
          found << mismatches.pop until mismatches.empty?

          Checks.expect(found, [], "a response was matched to the wrong request",
                        ids: ["TRANSPORT-29"],)
        end

        # PAGE-36 (phase 7c's per-call-options conformance test): the same transport driven twice
        # in sequence with DIFFERENT RequestOptions honours each -- not TRANSPORT-5's concurrent
        # pair, and not the same options twice, which would pass against a transport that reads
        # options once and reuses them for every later page.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def sequential_calls_honour_each_calls_options(kase)
          kase.wire(script: Scripts.sequenced("page one", "page two"))
          transport = kase.transport
          first = kase.settle(transport, kase.request, Checks.options(timeout: 5.0)).body_string
          second = kase.settle(transport, kase.request,
                               Checks.options(timeout: 0.5, max_retries: 0),).body_string

          Checks.expect([first, second], ["page one", "page two"],
                        "the second call did not reach a fresh page under its own options",
                        ids: ["PAGE-36"],)
        end

        # The registry's rows, `[ids, name, function]`, in the group's order.
        ROWS = [
          ["TRANSPORT-5", "two concurrent calls with different per-call timeouts are each " \
                          "bounded by their own",
           :concurrent_per_call_timeouts_bound_their_own_calls,],
          ["TRANSPORT-6", "a near-zero per-call timeout never becomes an unbounded one",
           :a_near_zero_timeout_never_becomes_unbounded,],
          ["TRANSPORT-15", "a borrowed client survives the transport's close and stays usable",
           :borrowed_client_survives_the_transports_close,],
          [%w[TRANSPORT-15 TRANSPORT-16], "an owned transport raises ClosedError on a send after " \
                                          "close, and close is idempotent",
           :owned_transport_refuses_a_send_after_close,],
          ["TRANSPORT-29", "many concurrent calls through one transport each get their own " \
                           "response", :concurrent_calls_each_get_their_own_response,],
          ["PAGE-36", "the same transport driven twice in sequence honours a different " \
                      "RequestOptions each time", :sequential_calls_honour_each_calls_options,],
        ].freeze
        private_constant :ROWS

        # The registry, built from ROWS.
        ASSERTIONS = Checks.registry(self, ROWS)

        private

        def timed_settle(kase, transport, request, seconds)
          Checks.timed_error do
            kase.settle(transport, request, Checks.options(timeout: seconds))
          end.last
        end

        # Every failure is recorded as a mismatch and never raised out of the thread, so the
        # eight threads are always joined and a broken transport fails the assertion rather than
        # leaking a thread.
        def echo_round_trips(kase, transport, thread_index, mismatches)
          20.times do |index|
            path = "/#{thread_index}-#{index}"
            body = kase.settle(transport, kase.request(path: path)).body_string
            mismatches.push([path, body]) unless body == path
          rescue ::StandardError => error
            mismatches.push([path, "#{error.class}: #{error.message}"])
          end
        end
      end
      private_constant :Lifecycle
    end
  end
end
