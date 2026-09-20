# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "../scripts"
require_relative "checks"

module Dexpace
  module Conformance
    module TransportSuite
      # Group 1, outbound mapping: TRANSPORT-10, TRANSPORT-11, TRANSPORT-26, and the wire-boundary
      # re-validation phase 1 postponed to every adapter (HTTP-17, HTTP-18, XCUT-18). Every send
      # goes through `kase.settle` (suite contract clause 8), every header is read back from the
      # fixture by a FOLDED name (clause 6), and what is asserted is the wire -- a real socket is
      # the only faithful witness of what left the process. A private_constant of TransportSuite.
      module Outbound
        extend self

        # A media type every adapter's native client would otherwise be tempted to stamp on a body
        # nobody described: it is a claim about the bytes that nobody made (8a's P8-4).
        FORM = "application/x-www-form-urlencoded"

        # TRANSPORT-10 (a): "body media type X with explicit Content-Type Y -> Y on the wire".
        #
        # @param kase [TransportCase]
        # @return [nil]
        def explicit_content_type_wins(kase)
          kase.wire(script: Scripts.fixed("ok"))
          headers = Checks.headers("Content-Type" => "text/plain")
          request = kase.request(method: "POST", headers: headers,
                                 body: Checks.bytes_body("{}", media_type: Checks.json),)
          kase.settle(kase.transport, request).close

          Checks.expect(Checks.last_request(kase, ids: ["TRANSPORT-10"]).header("content-type"),
                        "text/plain", "the caller's explicit Content-Type was overwritten",
                        ids: ["TRANSPORT-10"],)
        end

        # TRANSPORT-10 (b): "same body with no explicit header -> X on the wire".
        #
        # @param kase [TransportCase]
        # @return [nil]
        def body_media_type_when_caller_set_none(kase)
          kase.wire(script: Scripts.fixed("ok"))
          body = Checks.bytes_body("{}", media_type: Checks.json)
          kase.settle(kase.transport, kase.request(method: "POST", body: body)).close

          Checks.expect(Checks.last_request(kase, ids: ["TRANSPORT-10"]).header("content-type"),
                        "application/json", "the body's media type was not used",
                        ids: ["TRANSPORT-10"],)
        end

        # TRANSPORT-10, the case the requirement does not spell out: no explicit header and a body
        # with no media type. What the wire carries then is the adapter's (8a stamps RFC 9110's
        # application/octet-stream, asserted in its own suite); what it MUST NOT carry is a form
        # type nobody asked for, which is what a native client left to itself stamps.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def no_type_is_never_invented_as_a_form(kase)
          kase.wire(script: Scripts.fixed("ok"))
          kase.settle(kase.transport,
                      kase.request(method: "POST", body: Checks.bytes_body("raw")),).close
          sent = Checks.last_request(kase, ids: ["TRANSPORT-10"]).header("content-type")

          Checks.check(sent != FORM, "a body with no media type went out as a form",
                       ids: ["TRANSPORT-10"], expected: "anything but #{FORM}", actual: sent,)
        end

        # TRANSPORT-26: a body-less request on a body-permitted method is valid and goes out with
        # a zero-length body, `Content-Length: 0`.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def body_less_post_is_a_zero_length_body(kase)
          kase.wire(script: Scripts.fixed("ok"))
          response = kase.settle(kase.transport, kase.request(method: "POST"))
          status = response.status.code
          response.close
          sent = Checks.last_request(kase, ids: ["TRANSPORT-26"])

          Checks.expect(status, 200, "a body-less POST did not succeed", ids: ["TRANSPORT-26"])
          Checks.expect([sent.header("content-length"), sent.body], ["0", ""],
                        "a body-less POST was not substituted with a zero-length body",
                        ids: ["TRANSPORT-26"],)
        end

        # TRANSPORT-11's own clause: "send a bogus Content-Length/Host plus a pass-through header;
        # assert the framing headers are recomputed and the pass-through survives". Two checks,
        # because one passing while the other fails is the interesting outcome.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def framing_recomputed_and_pass_through_kept(kase)
          kase.wire(script: Scripts.fixed("ok"))
          headers = Checks.headers("Content-Length" => "9999", "Host" => "bogus.example",
                                   "X-Pass" => "kept",)
          request = kase.request(method: "POST", body: Checks.bytes_body("abc"), headers: headers)
          kase.settle(kase.transport, request).close
          sent = Checks.last_request(kase, ids: ["TRANSPORT-11"])

          Checks.expect([sent.header("content-length"), sent.header("host") == "bogus.example"],
                        ["3", false], "the framing headers were not recomputed",
                        ids: ["TRANSPORT-11"],)
          Checks.expect(sent.header("x-pass"), "kept", "the pass-through header vanished",
                        ids: ["TRANSPORT-11"],)
        end

        # HTTP-17 / XCUT-18: a forged request -- one that never met a builder, the hole design
        # §10.10 admits -- carrying a CRLF in a header NAME is refused before any byte reaches the
        # socket. The name half is the one with no native backstop on Net::HTTP (8a's verified
        # fact), which is why it is its own assertion.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def forged_header_name_is_rejected_before_dispatch(kase)
          refuses_forged_header(kase, "X-Evil\r\nInjected", "v", ids: %w[HTTP-17 XCUT-18])
        end

        # HTTP-18 / XCUT-18: the same, for a CRLF in a header VALUE.
        #
        # @param kase [TransportCase]
        # @return [nil]
        def forged_header_value_is_rejected_before_dispatch(kase)
          refuses_forged_header(kase, "X-Evil", "a\r\nInjected: 1", ids: %w[HTTP-18 XCUT-18])
        end

        # The registry's rows, `[ids, name, function]`, in the group's order.
        ROWS = [
          ["TRANSPORT-10", "the caller's explicit Content-Type wins over the body's",
           :explicit_content_type_wins,],
          ["TRANSPORT-10", "a body-derived Content-Type is used only when the caller set none",
           :body_media_type_when_caller_set_none,],
          ["TRANSPORT-10", "no explicit header and no body media type is never a form type",
           :no_type_is_never_invented_as_a_form,],
          ["TRANSPORT-26", "a body-less POST goes out as a zero-length body",
           :body_less_post_is_a_zero_length_body,],
          ["TRANSPORT-11", "a bogus Content-Length and Host are recomputed and a pass-through " \
                           "header survives", :framing_recomputed_and_pass_through_kept,],
          [%w[HTTP-17 XCUT-18], "wire-boundary re-validation: a forged CRLF header name is " \
                                "rejected before dispatch",
           :forged_header_name_is_rejected_before_dispatch,],
          [%w[HTTP-18 XCUT-18], "wire-boundary re-validation: a forged CRLF header value is " \
                                "rejected before dispatch",
           :forged_header_value_is_rejected_before_dispatch,],
        ].freeze
        private_constant :ROWS

        # The registry, built from ROWS.
        ASSERTIONS = Checks.registry(self, ROWS)

        private

        # A request-shaped object answering the four readers the seam contract types nothing about
        # (SEAM-11), carrying one forged header no Dexpace validation has ever seen. The socket
        # count is the check that discriminates: Dexpace::Response.build refuses a request that is
        # not a Dexpace::Request, so an adapter that skipped the re-validation and SENT the bytes
        # still raises InvalidArgumentError -- after the injected header reached the wire.
        def refuses_forged_header(kase, name, value, ids:)
          kase.wire(script: Scripts.fixed("ok"))
          forged = forged_request(kase.request, name, value)
          error = Checks.error_from { kase.settle(kase.transport, forged) }

          Checks.check(error.is_a?(Dexpace::InvalidArgumentError),
                       "a forged CRLF header reached the adapter unrejected",
                       ids: ids, expected: "Dexpace::InvalidArgumentError", actual: error&.class,)
          Checks.expect(kase.wire.connections, 0, "the forged request reached the socket", ids: ids)
        end

        def forged_request(template, name, value)
          headers = Object.new
          headers.define_singleton_method(:each_entry) { |&block| block.call(name, value) }
          forged = Object.new
          forged.define_singleton_method(:method) { template.method }
          forged.define_singleton_method(:url) { template.url }
          forged.define_singleton_method(:headers) { headers }
          forged.define_singleton_method(:body) { nil }
          forged
        end
      end
      private_constant :Outbound
    end
  end
end
