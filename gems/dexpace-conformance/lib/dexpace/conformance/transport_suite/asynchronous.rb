# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "../scripts"
require_relative "checks"

module Dexpace
  module Conformance
    module TransportSuite
      # Group 6, phase 8c's cancellation and delivery rows driven through the contract's
      # primitives: TRANSPORT-7, TRANSPORT-9, TRANSPORT-21 and TRANSPORT-23 (its two header-drop
      # rows, TRANSPORT-12 and TRANSPORT-13, are group 7, HeaderDrops). Every one is written
      # against `kase.settle`, `kase.wire` and Dexpace::Cancellation -- and nothing else, so no
      # reactor, task or native class is named here and the gem stays at dexpace-core alone. A
      # cancellation is fired through the token, because the contract exposes no future; on an
      # async driver `settle:` awaits the future the token settles, on a sync one the token is
      # what the blocked send observes, and the requirement's observable -- the native exchange
      # released, the cancellation terminal -- is the same on both. TRANSPORT-8 is NOT here: its
      # antecedent is a cancellation the host runtime originates, which only an adapter's own
      # suite can name (PREAMBLE says so). A private_constant of TransportSuite.
      module Asynchronous
        extend self

        # TRANSPORT-7's clause, "cancel an in-flight future and assert the native call is
        # cancelled", through the token: the head has arrived and the body is what blocks, the
        # token is cancelled on a second thread once the server has written the head, and the
        # cancellation surfaces terminal -- from the send when the adapter reads eagerly, from the
        # body read when it streams -- with the server observing the connection released.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def cancelling_the_token_mid_body_releases_the_exchange(kase)
          source = Dexpace::Cancellation.source
          written = ::Thread::Queue.new
          on_headers_written = -> { written.push(true) }
          kase.wire(script: Scripts.hang_after_headers(on_headers_written: on_headers_written))
          canceller = cancel_when(written, source, :conformance_mid_body)
          error = Checks.error_from do
            kase.settle(kase.transport, kase.request, Dexpace::RequestOptions::EMPTY, source.token)
              .body_string
          end
          canceller.join

          expect_terminal_cancellation(kase, error, "TRANSPORT-7",
                                       misclassified: "a mid-body cancellation did not surface " \
                                                      "as the terminal interrupt",
                                       unreleased: "the cancelled exchange did not release its " \
                                                   "connection",)
        end

        # TRANSPORT-9: the token is cancelled while the send is blocked on the head, and THEN the
        # server answers in full -- a native response delivered after the SDK side has already
        # cancelled. It must not be delivered, and the connection it arrived on must be released.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def a_response_arriving_after_cancellation_is_closed_not_delivered(kase)
          source = Dexpace::Cancellation.source
          blocked = ::Thread::Queue.new
          answer = ::Thread::Queue.new
          kase.wire(script: gated_answer(blocked, answer))
          canceller = cancel_when(blocked, source, :conformance_late_answer) { answer.push(true) }
          error = Checks.error_from do
            kase.settle(kase.transport, kase.request, Dexpace::RequestOptions::EMPTY, source.token)
          end
          canceller.join

          expect_terminal_cancellation(kase, error, "TRANSPORT-9",
                                       misclassified: "a response arriving after the " \
                                                      "cancellation was delivered or misclassified",
                                       unreleased: "the late response's connection was not " \
                                                   "released",)
        end

        # TRANSPORT-21: a failure raised while the request is adapted -- the body's own
        # `#content_length` raising, which no adapter can know in advance -- comes back through the
        # send primitive's failure channel classified as one of the SDK's own errors, never as the
        # raw exception thrown past it. On an async driver the primitive awaits the future, so a
        # classified failure here is one the future carried.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def an_adaptation_failure_is_delivered_classified(kase)
          kase.wire(script: Scripts.fixed("ok"))
          error = Checks.error_from do
            kase.settle(kase.transport, kase.request(method: "POST", body: RaisingBody.new)).close
          end

          Checks.check(error.is_a?(Dexpace::Error),
                       "an adaptation failure escaped the send contract unclassified",
                       ids: ["TRANSPORT-21"], expected: "a Dexpace::Error", actual: error&.class,)
        end

        # TRANSPORT-23: a success is always a Dexpace::Response, for a 204 with no body as for a
        # 200 with one; a transport with no response completes exceptionally instead.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def a_success_always_carries_a_response(kase)
          kase.wire(script: Scripts.sequenced("ok", ""))
          transport = kase.transport
          settled = Array.new(2) { kase.settle(transport, kase.request) }
          settled.each { |response| Dexpace.close_quietly(response) }

          Checks.expect(settled.map(&:class), [Dexpace::Response, Dexpace::Response],
                        "a success settled with something other than a Dexpace::Response",
                        ids: ["TRANSPORT-23"],)
        end

        # The registry's rows, `[ids, name, function]`, in the group's order.
        ROWS = [
          ["TRANSPORT-7", "cancelling the token mid-body releases the native exchange as the " \
                          "terminal interrupt",
           :cancelling_the_token_mid_body_releases_the_exchange,],
          ["TRANSPORT-9", "a response arriving after the cancellation is closed, never delivered",
           :a_response_arriving_after_cancellation_is_closed_not_delivered,],
          ["TRANSPORT-21", "an adaptation failure is delivered classified through the send " \
                           "primitive's failure channel",
           :an_adaptation_failure_is_delivered_classified,],
          ["TRANSPORT-23", "a success always carries a Dexpace::Response, even with no body",
           :a_success_always_carries_a_response,],
        ].freeze
        private_constant :ROWS

        # The registry, built from ROWS.
        ASSERTIONS = Checks.registry(self, ROWS)

        # A body whose adaptation fails: every adapter asks a body's length or pulls it before or
        # while dispatching, and this one raises the moment either happens.
        class RaisingBody
          include Dexpace::Body

          # Raises: the adaptation's first question about the body.
          #
          # @raise [RuntimeError] always
          def content_length
            raise "the body's own content_length failed during adaptation"
          end

          # Raises: the adaptation's other route into the body.
          #
          # @raise [RuntimeError] always
          def write_to(_sink)
            raise "the body's own write failed during adaptation"
          end
        end
        private_constant :RaisingBody

        private

        # The second thread both cancellation rows need: waits for the fixture's signal, cancels
        # the token with the given reason, then runs the block -- how TRANSPORT-9 lets the server
        # answer only after the cancel has landed.
        def cancel_when(signal, source, reason)
          ::Thread.new do
            signal.pop
            source.cancel(reason)
            yield if block_given?
          end
        end

        # Holds the connection after reading the request until `answer` says so, then answers in
        # full: the shape TRANSPORT-9 needs and no named script has.
        def gated_answer(blocked, answer)
          lambda do |conn, _head|
            blocked.push(true)
            answer.pop
            Scripts.write_response(conn, body: "late")
          end
        end

        # Both cancellation rows' outcome: the terminal interrupt, and the connection released.
        def expect_terminal_cancellation(kase, error, id, misclassified:, unreleased:)
          Checks.expect(error.class, Dexpace::CancelledError, misclassified, ids: [id])
          Checks.check_connection_released(kase, ids: [id], message: unreleased)
        end
      end
      private_constant :Asynchronous
    end
  end
end
