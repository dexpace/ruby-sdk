# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# XCUT-18's call-site assertion observes wire activity rather than inferring it, so it owns a
# listener for the length of one assertion. `socket` is reachable to THIS gem alone: the require
# allowlist's denial is scoped to dexpace-core and the transport adapters, whose wire access goes
# through the one gem each declares (phase 8a's P8-14).
require "socket"
require_relative "../check"
require_relative "../runner"
require_relative "../vacuous"
require_relative "outcomes"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 6, XCUT-18's two assertions: the model layer's validator and the adapter's
      # re-validation at the call site. A private_constant of InvariantSuite.
      module HeaderSyntax
        extend self

        # HTAB is the ONE byte a NAME must reject and a VALUE must accept; the asymmetry IS the
        # requirement, and a port applying one rule to both passes a single-case check.
        NAME_REJECTS = { "CR" => "\r", "LF" => "\n", "NUL" => "\x00", "DEL" => "\x7F",
                         "HTAB" => "\t", "non-ASCII" => "\xC3\xA5", }.freeze
        # Every control byte XCUT-18 refuses in a value, HTAB deliberately absent.
        VALUE_REJECTS = NAME_REJECTS.except("HTAB")
        # A header name no builder would ever produce: the CRLF in it is the injection.
        FORGED_NAME = "X-Evil\r\nInjected"

        # XCUT-18 at the MODEL layer: "names MUST reject all C0 control bytes (including CR, LF,
        # NUL and HTAB) and DEL. Outbound values MUST reject the same set EXCEPT horizontal tab.
        # Both MUST reject non-ASCII bytes."
        def header_syntax_validation(subject)
          subject.probe!(:HeaderSyntax, "phase 1's HeaderSyntax")
          syntax = subject.core.const_get(:HeaderSyntax)

          NAME_REJECTS.each do |label, byte|
            Check.that(Outcomes.refused?(-> { syntax.validate_name!("X-A#{byte}B") }),
                       "a header NAME containing #{label} was accepted",
                       expected: "rejected", actual: "accepted", ids: ["XCUT-18"],)
          end
          check_values(syntax)
          nil
        end

        # XCUT-18 at the CALL SITE -- the wire-boundary re-validation phase 1 postponed to every
        # adapter and named this phase's suite as the home of the assertion that it happened.
        #
        # Phase 8's own per-adapter tests prove the call site in two first-party adapters; a
        # property asserted only there is one a THIRD-PARTY adapter omits silently. The forged
        # request never met a builder -- that is the point -- and wire activity is OBSERVED, not
        # inferred: the URL names a listener this assertion owns, and one accepted connection is
        # the failure. The listener is acquired and released in this method's own scope with an
        # ensure, never inside an Enumerator (§7.1).
        def forged_request_is_refused_at_dispatch(subject)
          unless subject.transport?
            raise Vacuous,
                  "no transport factory supplied to InvariantSuite.run"
          end

          subject.probe!(:Request, "phase 1's domain model")
          listener = listen
          begin
            check_dispatch(subject, listener)
          ensure
            listener.close
          end
        end

        # The VALUE half of XCUT-18's asymmetry: HTAB admitted, every other control refused.
        # @return [void]
        def check_values(syntax)
          Check.that(!Outcomes.refused?(lambda {
            syntax.validate_outbound_value!("a\tb", name: "X-T")
          }),
                     "an outbound VALUE containing HTAB was rejected; only a NAME must reject it",
                     expected: "accepted", actual: "rejected", ids: ["XCUT-18"],)
          VALUE_REJECTS.each do |label, byte|
            Check.that(Outcomes.refused?(lambda {
              syntax.validate_outbound_value!("a#{byte}b", name: "X-T")
            }),
                       "an outbound VALUE containing #{label} was accepted",
                       expected: "rejected", actual: "accepted", ids: ["XCUT-18"],)
          end
        end

        # @return [nil] the two observations together: no connection, and a raise
        def check_dispatch(subject, listener)
          forged, route = forge(subject.core, "http://127.0.0.1:#{listener.addr[1]}/")
          refused = Outcomes.refused?(lambda {
            subject.transport.call(forged, nil, subject.core.const_get(:Cancellation).none)
          })
          connected = listener.accept_nonblock(exception: false) != :wait_readable

          Check.that(!connected,
                     "the adapter accepted a connection for a request forged via #{route} whose " \
                     "header name carries CRLF",
                     expected: "no wire activity", actual: "accepted a connection",
                     ids: ["XCUT-18"],)
          Check.that(refused,
                     "the adapter did not raise on a forged request (via #{route}) whose header " \
                     "name carries CRLF",
                     expected: "raised before dispatch", actual: "returned", ids: ["XCUT-18"],)
        end

        # Through an untyped local, exactly as 8a's WireServer does: rbs 4.2.0 reads
        # `TCPServer#initialize: (?String host, Integer port)` as a single optional positional, so
        # the two-argument call Ruby accepts is refused by the checker and not by Ruby.
        def listen
          server_class = ::TCPServer #: untyped
          server_class.new("127.0.0.1", 0)
        end

        # Two forged shapes, tried in order. Neither goes through Headers.build, because HTTP-17
        # rejects the name there -- which is exactly why a forged model is the one that must be
        # re-validated at the wire boundary (design §10.10's documented `send` hole).
        def forge(core, url)
          headers = Object.new
          headers.define_singleton_method(:each_entry) { |&block| block.call(FORGED_NAME, "v") }
          parsed = core.const_get(:URL).parse!(url)
          verb = core.const_get(:Method)::GET
          begin
            [core.const_get(:Request).send(:new, method: verb, url: parsed, headers: headers,
                                                 body: nil,),
             "Request.send(:new, ...)",]
          rescue ::StandardError
            [duck(verb, parsed, headers),
             "a duck-typed object answering #method/#url/#headers/#body",]
          end
        end

        # @return [Object] a request that never met a builder and never could
        def duck(verb, url, headers)
          forged = Object.new
          forged.define_singleton_method(:method) { verb }
          forged.define_singleton_method(:url) { url }
          forged.define_singleton_method(:headers) { headers }
          forged.define_singleton_method(:body) { nil }
          forged
        end

        ROWS = [
          ["XCUT-18", "header names and outbound values reject splitting bytes at the model layer",
           :header_syntax_validation,],
          ["XCUT-18", "an adapter refuses a forged request at dispatch, before any wire activity",
           :forged_request_is_refused_at_dispatch,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :HeaderSyntax
    end
  end
end
