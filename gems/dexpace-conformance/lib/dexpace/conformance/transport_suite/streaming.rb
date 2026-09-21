# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require "tempfile"
require_relative "../scripts"
require_relative "checks"

module Dexpace
  module Conformance
    module TransportSuite
      # Group 3, streaming and body lifecycle: TRANSPORT-25, TRANSPORT-19 and TRANSPORT-28's two
      # reachable clauses. A private_constant of TransportSuite.
      module Streaming
        extend self

        # TRANSPORT-25's "multi-megabyte": ~5 MiB of a non-uniform pattern, compared byte for byte.
        LARGE_BYTES = (5 * 1024 * 1024) + 26

        # TRANSPORT-25's clause: "stream a multi-megabyte response and assert byte-exact round-trip;
        # assert closing returns the connection" -- the second half observed from the server, which
        # holds the connection until the peer closes it.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def multi_megabyte_body_round_trips_and_close_releases(kase)
          expected = Scripts.large_body(LARGE_BYTES)
          kase.wire(script: Scripts.large(LARGE_BYTES, hold: true))
          response = kase.settle(kase.transport, kase.request)
          drained = response.body_bytes.to_s # reads the whole stream and closes the response

          Checks.check(drained == expected, "the body did not round-trip byte-exactly",
                       ids: ["TRANSPORT-25"], expected: "#{expected.bytesize} bytes",
                       actual: "#{drained.bytesize} bytes",)
          Checks.check_connection_released(kase, ids: ["TRANSPORT-25"],
                                                 message: "closing the response did not release " \
                                                          "the connection",)
        end

        # TRANSPORT-19: closing an undrained response whose producer is blocked mid-body unblocks
        # it promptly, and the teardown is idempotent. The server's gap is five seconds, so a close
        # that waited for the producer would take five seconds and the one-second bound catches it.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def closing_an_undrained_response_is_prompt_and_idempotent(kase)
          kase.wire(script: Scripts.dribble("aaaaa", "bbbbb", 5.0))
          response = kase.settle(kase.transport, kase.request)
          took = Checks.elapsed do
            response.close
            response.close
          end

          Checks.check(took < 1.0, "closing an undrained, dribbling response blocked",
                       ids: ["TRANSPORT-19"], expected: "< 1.0 s", actual: took,)
        end

        # TRANSPORT-28's clause: "upload a file body with a non-zero position and partial count;
        # assert exactly that byte range reaches the wire" -- and its embedded MUST, the body is
        # replayable. The file is created with the block-less Tempfile.create: the block form
        # unlinks the path at block exit, before the request would read it (8a, measured).
        #
        # @param kase [TransportCase]
        # @return [nil]
        def file_body_window_reaches_the_wire(kase)
          kase.wire(script: Scripts.fixed("ok"))
          path = window_file("0123456789")
          body = Dexpace::Body.file(path, offset: 3, count: 4) # "3456"
          kase.settle(kase.transport, kase.request(method: "POST", body: body)).close
          sent = Checks.last_request(kase, ids: ["TRANSPORT-28"])

          Checks.expect([body.replayable?, sent.header("content-length"), sent.body],
                        [true, "4", "3456".b], "the file body's byte range was not honoured",
                        ids: ["TRANSPORT-28"],)
        ensure
          ::File.unlink(path) if path && ::File.exist?(path)
        end

        # The registry's rows, `[ids, name, function]`, in the group's order.
        ROWS = [
          ["TRANSPORT-25", "a multi-megabyte body round-trips byte-exactly and closing returns " \
                           "the connection", :multi_megabyte_body_round_trips_and_close_releases,],
          ["TRANSPORT-19", "closing an undrained response unblocks the producer promptly and " \
                           "idempotently",
           :closing_an_undrained_response_is_prompt_and_idempotent,],
          ["TRANSPORT-28", "a file body with a non-zero position and partial count sends exactly " \
                           "that range", :file_body_window_reaches_the_wire,],
        ].freeze
        private_constant :ROWS

        # The registry, built from ROWS.
        ASSERTIONS = Checks.registry(self, ROWS)

        private

        def window_file(content)
          file = ::Tempfile.create("dexpace-conformance")
          file.write(content)
          file.close
          file.path
        end
      end
      private_constant :Streaming
    end
  end
end
