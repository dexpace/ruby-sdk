# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "../vacuous"
require_relative "../scripts"
require_relative "checks"

module Dexpace
  module Conformance
    module TransportSuite
      # Group 4, retry, cancellation and failure classification: TRANSPORT-1, TRANSPORT-2,
      # TRANSPORT-3, TRANSPORT-4, TRANSPORT-17, TRANSPORT-18, TRANSPORT-20 and TRANSPORT-22. A
      # cancellation is asserted as Dexpace::CancelledError out of `kase.settle` (suite contract
      # clause 5), a failure carrying no response as something answering #retryable? true (the
      # phase-level Dexpace::TransportError), and every cancellation is fired through the
      # Dexpace::Cancellation token and never a thread interrupt. A private_constant of
      # TransportSuite.
      module Resilience
        extend self

        # TRANSPORT-1: a raw 302 with a Location comes back as it is and is never followed.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def redirect_is_returned_never_followed(kase)
          kase.wire(script: Scripts.redirect("http://elsewhere.invalid/"))
          response = kase.settle(kase.transport, kase.request)
          seen = [response.status.code, response.headers["Location"], kase.wire.requests.size]
          response.close

          Checks.expect(seen, [302, ["http://elsewhere.invalid/"], 1], "a redirect was followed",
                        ids: ["TRANSPORT-1"],)
        end

        # TRANSPORT-2's clause: "with a single-use body and a first-attempt connection failure,
        # assert the native client does not silently re-send" -- a COUNT of connections and of
        # body pulls, not an inference from the error.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def first_attempt_failure_is_not_silently_resent(kase)
          seen = Checks.dropped_first_attempt(kase)

          Checks.expect(seen, { raised: true, connections: 1, pulls: 1 },
                        "the failed first attempt was silently retried", ids: ["TRANSPORT-2"],)
        end

        # TRANSPORT-3: a caller-initiated cancellation while the send is blocked surfaces as the
        # terminal, non-retryable interrupt -- Dexpace::CancelledError -- and never as the
        # retryable failure, with the token still reporting cancelled afterwards. The cancel fires
        # when the SERVER says the client is blocked waiting for the head (the script's hook), on
        # a second thread, through the token: a blocking Queue#pop, never a sleep and never an
        # interrupt.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def cancellation_surfaces_as_the_interrupt(kase)
          source = Dexpace::Cancellation.source
          canceller = Checks.cancel_when_blocked(kase, source)
          error = Checks.error_from do
            kase.settle(kase.transport, kase.request, Dexpace::RequestOptions::EMPTY, source.token)
          end
          canceller.join

          Checks.expect([error.class, source.cancelled?], [Dexpace::CancelledError, true],
                        "the cancellation was swallowed or misclassified", ids: ["TRANSPORT-3"],)
        end

        # TRANSPORT-4's clause: a read timeout classifies as the RETRYABLE transport failure and
        # leaves the cancellation flag clear.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def read_timeout_is_retryable_and_sets_no_cancellation(kase)
          kase.wire(script: Scripts.hang_before_headers)
          source = Dexpace::Cancellation.source
          error = Checks.error_from do
            kase.settle(kase.transport(timeout: 0.2), kase.request, Dexpace::RequestOptions::EMPTY,
                        source.token,)
          end
          seen = [Checks.retryable_failure?(error), error.is_a?(Dexpace::CancelledError),
                  source.cancelled?,]

          Checks.expect(seen, [true, false, false],
                        "a read timeout did not classify retryable, or set the cancellation flag",
                        ids: ["TRANSPORT-4"],)
        end

        # TRANSPORT-17: a single-use body is written exactly once, and the adapter itself triggers
        # no second write -- one connection, one request, one pull, the bytes intact.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def single_use_body_is_written_once(kase)
          kase.wire(script: Scripts.fixed("ok"))
          body, pulls = Checks.single_use_body("payload")
          kase.settle(kase.transport, kase.request(method: "POST", body: body)).close
          requests = kase.wire.requests

          Checks.expect([requests.size, pulls.call, requests.last&.body], [1, 1, "payload".b],
                        "the single-use body was written more than once", ids: ["TRANSPORT-17"],)
        end

        # TRANSPORT-18 conditions on a native body API that "drives writes through a re-subscribable
        # producer" on its own retry or redirect. The antecedent is not asserted from a list; it is
        # MEASURED: a single-use body over a dropped first connection is pulled once and the client
        # opens one connection, so nothing native re-subscribed, and the requirement holds
        # vacuously on this adapter. An adapter whose native client did re-send fails here instead
        # of being recorded vacuous.
        #
        # @param kase [TransportCase]
        # @return [void]
        # @raise [Vacuous] when the measurement shows the antecedent absent
        def no_native_resubscription_measured(kase)
          seen = Checks.dropped_first_attempt(kase)

          Checks.expect([seen[:connections], seen[:pulls]], [1, 1],
                        "the native client re-subscribed the body producer on its own",
                        ids: ["TRANSPORT-18"],)
          raise Vacuous, "the native client opened one connection and pulled the single-use body " \
                         "once across a dropped first attempt, so no re-subscribable producer is " \
                         "in play on this adapter (TRANSPORT-18's antecedent is absent)"
        end

        # TRANSPORT-20: a connection refused surfaces as the canonical retryable transport failure.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def connection_refused_is_the_retryable_failure(kase)
          request = kase.request # against the fixture's port, which stops listening next
          kase.wire.close
          error = Checks.error_from { kase.settle(kase.transport, request) }

          Checks.check(Checks.retryable_failure?(error), "a refused connection was not retryable",
                       ids: ["TRANSPORT-20"], expected: "a retryable transport failure",
                       actual: error&.class,)
        end

        # TRANSPORT-22's observable half from outside the adapter: when the CALLER's own code
        # fails after a live response arrived and closes it, the connection is released -- the
        # server, holding the connection, sees the close. The adaptation-failure half is asserted
        # in the adapter's own suite, where a failure can be injected after the head.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def caller_failure_after_head_releases_the_connection(kase)
          kase.wire(script: Scripts.fixed("ok", hold: true))
          response = kase.settle(kase.transport, kase.request)
          begin
            raise "caller-injected failure after the head arrived"
          rescue ::RuntimeError
            response.close
          end

          Checks.check_connection_released(kase, ids: ["TRANSPORT-22"],
                                                 message: "the connection was not released",)
        end

        # The registry's rows, `[ids, name, function]`, in the group's order.
        ROWS = [
          ["TRANSPORT-1", "a raw 302 is returned, never followed",
           :redirect_is_returned_never_followed,],
          ["TRANSPORT-2", "a single-use body over a first-attempt connection failure is not " \
                          "silently re-sent", :first_attempt_failure_is_not_silently_resent,],
          ["TRANSPORT-3", "a mid-send cancellation surfaces as the interrupt, not the retryable " \
                          "failure", :cancellation_surfaces_as_the_interrupt,],
          ["TRANSPORT-4", "a read timeout classifies retryable and leaves no cancellation flag set",
           :read_timeout_is_retryable_and_sets_no_cancellation,],
          ["TRANSPORT-17", "a single-use body is written exactly once and never re-written by " \
                           "the adapter", :single_use_body_is_written_once,],
          ["TRANSPORT-18", "vacuous by measurement: no native re-subscribable body producer is " \
                           "in play", :no_native_resubscription_measured,],
          ["TRANSPORT-20", "a connection refused surfaces as the canonical retryable transport " \
                           "failure", :connection_refused_is_the_retryable_failure,],
          ["TRANSPORT-22", "a caller failure after a live response arrived still releases the " \
                           "connection", :caller_failure_after_head_releases_the_connection,],
        ].freeze
        private_constant :ROWS

        # The registry, built from ROWS.
        ASSERTIONS = Checks.registry(self, ROWS)
      end
      private_constant :Resilience
    end
  end
end
