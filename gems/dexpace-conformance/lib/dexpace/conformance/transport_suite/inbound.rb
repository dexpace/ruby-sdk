# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "../scripts"
require_relative "checks"

module Dexpace
  module Conformance
    module TransportSuite
      # Group 2, inbound mapping: TRANSPORT-24, TRANSPORT-14 and TRANSPORT-27. Every question is
      # asked of the Dexpace::Response -- the status, the folded header lookup, the body's own
      # `content_length` and `media_type` -- and never of a native object (suite contract clauses
      # 2, 6 and 7). A private_constant of TransportSuite.
      module Inbound
        extend self

        # What TRANSPORT-14's script must come back as: the control-byte value and the non-ASCII
        # name dropped, the obs-text value kept, the body read.
        LENIENT = { control_byte_dropped: true, non_ascii_name_dropped: true, obs_text_kept: true,
                    body: "hi", }.freeze

        # TRANSPORT-24's clause: "a 520 with a body" surfaces faithfully.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def vendor_status_surfaces_faithfully(kase)
          kase.wire(script: Scripts.vendor_status(520, "vendor error"))
          response = kase.settle(kase.transport, kase.request)

          Checks.expect([response.status.code, response.body_string], [520, "vendor error"],
                        "a vendor status was not surfaced faithfully", ids: ["TRANSPORT-24"],)
        end

        # TRANSPORT-14's clause: a control-byte value and a non-ASCII name are dropped, an obs-text
        # value is preserved, and the body and the remaining headers are still delivered.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def malformed_headers_are_dropped_one_at_a_time(kase)
          kase.wire(script: Scripts.malformed_headers)
          response = kase.settle(kase.transport, kase.request)

          Checks.expect(leniency_of(response), LENIENT,
                        "TRANSPORT-14's per-header leniency did not hold", ids: ["TRANSPORT-14"],)
        end

        # TRANSPORT-14, the multi-valued half: a repeated Set-Cookie survives as two values, which
        # is the assertion that fails if an adapter joins with ", " on the way in.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def multi_valued_header_survives(kase)
          kase.wire(script: Scripts.malformed_headers)
          response = kase.settle(kase.transport, kase.request)
          values = response.headers["Set-Cookie"]
          response.close

          Checks.expect(values, ["a=1", "b=2"], "a multi-valued header collapsed",
                        ids: ["TRANSPORT-14"],)
        end

        # TRANSPORT-27's clause: "a malformed Content-Type and non-numeric Content-Length still
        # let the body read, with null media type and unknown length" -- the -1 sentinel on the
        # body, never nil and never read off a native object (clause 2).
        #
        # @param kase [TransportCase]
        # @return [nil]
        def malformed_type_and_length_downgrade(kase)
          kase.wire(script: Scripts.malformed_content_length)
          response = kase.settle(kase.transport, kase.request)
          body = response.body

          Checks.expect([body&.media_type, body&.content_length, response.body_string],
                        [nil, -1, "hi"], "TRANSPORT-27's downgrade did not hold",
                        ids: ["TRANSPORT-27"],)
        end

        # What TRANSPORT-14's script came back as, in LENIENT's shape.
        #
        # @param response [Dexpace::Response]
        # @return [Hash]
        def leniency_of(response)
          headers = response.headers
          { control_byte_dropped: !headers.include?("X-Ctl"),
            non_ascii_name_dropped: headers.names.none? { |name| name.b.include?("\xE9".b) },
            obs_text_kept: headers["X-Obs"] == ["caf\xE9".b], body: response.body_string, }
        end

        # The registry's rows, `[ids, name, function]`, in the group's order.
        ROWS = [
          ["TRANSPORT-24", "a vendor status code with a body is surfaced faithfully",
           :vendor_status_surfaces_faithfully,],
          ["TRANSPORT-14", "a control-byte value and a non-ASCII name are dropped while obs-text " \
                           "and the body survive", :malformed_headers_are_dropped_one_at_a_time,],
          ["TRANSPORT-14", "a multi-valued Set-Cookie survives as two values",
           :multi_valued_header_survives,],
          ["TRANSPORT-27", "a malformed Content-Type and a non-numeric Content-Length still let " \
                           "the body read", :malformed_type_and_length_downgrade,],
        ].freeze
        private_constant :ROWS

        # The registry, built from ROWS.
        ASSERTIONS = Checks.registry(self, ROWS)
      end
      private_constant :Inbound
    end
  end
end
