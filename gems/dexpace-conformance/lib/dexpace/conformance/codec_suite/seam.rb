# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../failure"
require_relative "../runner"
require_relative "../vacuous"

module Dexpace
  module Conformance
    module CodecSuite
      # The two portable seam properties, in a group of their own so the assertion bodies are not
      # public surface: every other suite's groups are private_constants and this one is too, which
      # is what keeps each suite's public surface exactly `assertions`, `run` and `PREAMBLE`.
      # A private_constant of CodecSuite.
      module Seam
        extend self

        # The value every encode assertion dumps: small, native, and encodable by any codec.
        SAMPLE = { "a" => 1 }.freeze
        # Input no codec can decode, which is SERDE-9's antecedent.
        MALFORMED = "{not json"

        # SEAM-20 and SERDE-3: a codec MUST NOT close a target it was handed. `#dump_to` and never
        # `#dump`: phase 2's CONTRACT names `#dump_to` and keeps the `#dump` shorthand out of it
        # deliberately, so a conforming codec need not define `#dump` at all. The bytes are checked
        # too, so a codec that wrote nothing cannot pass by having closed nothing.
        def never_closes_its_target(subject)
          sink = subject.sink
          subject.codec.dump_to(SAMPLE, sink)

          Check.that(sink.close_count.zero?, "the codec closed a caller-supplied sink",
                     expected: 0, actual: sink.close_count, ids: %w[SEAM-20 SERDE-3],)
          Check.that(!sink.bytes.empty?,
                     "the codec wrote nothing, so closing nothing proves nothing",
                     expected: "some bytes", actual: sink.bytes.bytesize,
                     ids: %w[SEAM-20 SERDE-3],)
        end

        # SERDE-9: "failures surface the stable serde type CHAINING THE ORIGINAL CAUSE, no library
        # type escapes." Three clauses and all three are asserted -- a Dexpace error OUTSIDE the
        # serde hierarchy, or a serde error with NO cause chained, satisfies neither the "stable
        # serde type" nor the "chaining the original cause" half.
        def no_library_type_escapes(subject)
          raised = capture_failure(subject)

          Check.that(!raised.nil?, "malformed input decoded without raising",
                     expected: "a Dexpace::Serde::Error", actual: "no error", ids: ["SERDE-9"],)
          Check.that(serde_error?(raised),
                     "a failure outside the SDK's serde hierarchy escaped the seam",
                     expected: "Dexpace::Serde::Error", actual: raised.class.name,
                     ids: ["SERDE-9"],)
          # The chain is read through core's ONE cause walk rather than through a bare
          # `raised.cause`: XCUT-9 makes `Dexpace.each_cause` the single walk, `gates:cause_walk`
          # keeps it single by scanning for any other `#cause` send, and that scan cannot tell a
          # one-step read from a walk. Using the walk costs nothing and keeps the gate's allowlist
          # at one entry.
          Check.that(::Dexpace.each_cause(raised).count > 1,
                     "the serde failure chained no original cause",
                     expected: "a chained #cause", actual: 1, ids: ["SERDE-9"],)
        end

        # Vacuous and Failure are re-RAISED rather than captured: both are ::StandardError
        # descendants (8a), so a bare rescue would turn this suite's own vacuity into a PASS.
        def capture_failure(subject)
          subject.codec.load(subject.source(MALFORMED), subject.witness)
          nil
        rescue Vacuous, Failure
          raise
        rescue ::StandardError => error
          error
        end

        def serde_error?(error)
          defined?(::Dexpace::Serde::Error) && error.is_a?(::Dexpace::Serde::Error)
        end

        ROWS = [
          [%w[SEAM-20 SERDE-3], "a codec never closes a target it was handed",
           :never_closes_its_target,],
          ["SERDE-9", "a decode failure surfaces the SDK's serde type", :no_library_type_escapes],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Seam
    end
  end
end
