# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"
require_relative "outcomes"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 3, the error factory, the cause walk and the retry-safety gate: XCUT-8, XCUT-9 and
      # XCUT-10. A private_constant of InvariantSuite.
      module Classification
        extend self

        # A cycle SHORTER than this cannot discriminate: a two-node cycle is indistinguishable
        # from a walk that simply stops after two steps, so a depth-capped implementation passes.
        CYCLE_NODES = 3
        # The step bound on the drive. A walk that never terminates raises StopIteration never, so
        # the drive is bounded by COUNT -- which needs none of §8.3's banned interrupt primitives
        # and is why the "a bound is unavailable" reasoning was simply false.
        MAX_STEPS = 8

        # Each assertion below is one requirement's CLAUSES, and each clause is one Check, so the
        # metric is counting the requirement's own size. Splitting by count would split by
        # arithmetic rather than by behaviour -- which is .rubocop.yml's own recorded argument for
        # turning Minitest/MultipleAssertions off, applied to the assertions that mirror them.
        # rubocop:disable Metrics/AbcSize
        # XCUT-8: "the status-to-exception mapping factory MUST reject being asked to map a
        # non-error status -- it MUST raise an argument error rather than fabricate a 'successful
        # exception'. A convenience form MAY instead return an absent/null value." Two forms, one
        # assertion, and the error form is checked for BOTH halves: it raises on 200 and it still
        # maps a real error status.
        def error_factory_refuses_non_error_status(subject)
          subject.probe!(:ProtocolError, "4b's recovery layer")
          factory = subject.core.const_get(:ProtocolError)
          refused = Outcomes.raised_class(-> { factory.for(response(subject, 200)) })

          Check.that(refused == subject.core.const_get(:InvalidArgumentError),
                     "the status-to-exception factory fabricated an error for a 2xx",
                     expected: "InvalidArgumentError", actual: refused, ids: ["XCUT-8"],)
          Check.that(factory.for_or_nil(response(subject, 200)).nil?,
                     "the convenience form returned something for a non-error status",
                     expected: nil, actual: "an error", ids: ["XCUT-8"],)
          mapped = factory.for(response(subject, 503))
          Check.that(mapped.status.code == 503, "the factory did not map a real error status",
                     expected: 503, actual: mapped.status.code, ids: ["XCUT-8"],)
        end

        # XCUT-9: "MUST track visited causes BY REFERENCE IDENTITY and terminate on a
        # self-referential or cyclic chain instead of looping forever."
        #
        # THREE nodes, not two, for the reason CYCLE_NODES states. The walk is driven through
        # Enumerator#next under a STEP BOUND rather than #to_a, so a non-terminating walk reports
        # :failed instead of hanging the suite.
        #
        # **Stated residue, because a green result must not read as more than it is.** A
        # collect-then-yield walk -- one that gathers the whole chain before yielding its first
        # element -- never returns a step to count, and bounding THAT would need an interrupt
        # §8.3 bans outright; the suite would hang, and only the harness's own outer bound would
        # end it. And a depth cap of exactly CYCLE_NODES passes: a black-box test over one finite
        # input cannot tell a counter from a visited set. gates:cause_walk is the second line,
        # keeping the walk in one file so neither defect can live anywhere else; it proves neither
        # absent. Both are on the XCUT-9 checklist row.
        def cycle_safe_cause_walk(subject)
          subject.probe!(:each_cause, "4b's Dexpace.each_cause", method: true)
          walked = drive(subject.core.each_cause(cycle))

          Check.that(walked.size == CYCLE_NODES,
                     "the cause walk did not terminate after visiting the cycle once",
                     expected: CYCLE_NODES, actual: walked.size, ids: ["XCUT-9"],)
          Check.that(walked.uniq(&:object_id).size == CYCLE_NODES,
                     "the cause walk revisited a node, so it does not track by reference identity",
                     expected: CYCLE_NODES, actual: walked.uniq(&:object_id).size, ids: ["XCUT-9"],)
        end

        # XCUT-10: "retry-SAFETY MUST be decided at the retry step, independently of retryability,
        # and applied UNIFORMLY to both protocol and transport failures: (a) a request WITHOUT a
        # body is retry-safe only if its method is in the configured idempotent-method set -- a
        # bare POST MUST NOT be retried, EVEN when the failure is a transport error that never
        # reached the server; (b) a request WITH a body is retry-safe only if that body is
        # replayable." The gate takes the REQUEST and nothing else, which is what makes the
        # uniformity structural: there is no failure parameter to special-case on.
        def retry_safety_is_uniform(subject)
          subject.probe!(:Resilience, "6a's retry layer")
          resend = subject.core::Resilience.const_get(:Resend)
          cases = { "a body-less GET" => [safety_request(subject, "GET", nil), true],
                    "a body-less POST" => [safety_request(subject, "POST", nil), false],
                    "a POST with a replayable body" => [replayable_post(subject), true],
                    "a POST with a streaming body" => [streaming_post(subject), false], }

          wrong = cases.reject { |_, (request, want)| resend.eligible?(request) == want }
          Check.that(wrong.empty?,
                     "the retry-safety gate does not decide every case XCUT-10 enumerates",
                     expected: cases.transform_values(&:last), actual: wrong.keys,
                     ids: ["XCUT-10"],)
          Check.that(resend.method(:eligible?).parameters == [%i[req request]],
                     "the safety gate takes a failure parameter, so it CAN special-case a " \
                     "transport error -- the uniformity XCUT-10 demands is structural",
                     expected: [%i[req request]], actual: resend.method(:eligible?).parameters,
                     ids: ["XCUT-10"],)
        end

        # Exception#cause is not assignable, so the cycle is built through a singleton reader --
        # the only portable way to produce the shape XCUT-9 names on CRuby, and the shape 4b's own
        # fixture uses.
        def cycle
          nodes = ::Array.new(CYCLE_NODES) { |i| ::StandardError.new("node-#{i}") }
          nodes.each_with_index do |node, index|
            node.instance_variable_set(:@dexpace_loop, nodes[(index + 1) % nodes.size])
            def node.cause = @dexpace_loop
          end
          nodes.first
        end

        # @return [Array<untyped>] at most the step bound, so a non-terminating walk still ends
        def drive(enumerator)
          walked = [] #: Array[untyped]
          collect(enumerator, walked)
          walked
        end

        # @return [nil] fills `walked` under the step bound, stopping at StopIteration
        def collect(enumerator, walked)
          MAX_STEPS.times { walked << enumerator.next }
          nil
        rescue ::StopIteration
          nil
        end

        # @return [untyped] a minimal response carrying the status under test
        def response(subject, code)
          subject.core::Response.build(
            request: safety_request(subject, "GET", nil),
            protocol: subject.core::Protocol::HTTP_1_1,
            status: subject.core::Status.of(code), headers: subject.core::Headers::EMPTY,
          )
        end

        # @return [untyped] a minimal request, which is the retry-safety gate's whole input
        def safety_request(subject, verb, body)
          subject.core::Request.build(method: subject.core::Method.of(verb),
                                      url: "https://a.example/x",
                                      headers: subject.core::Headers::EMPTY, body: body,)
        end

        # @return [untyped] a POST whose body answers `#replayable?` true
        def replayable_post(subject)
          safety_request(subject, "POST", subject.core::Body.string("{}"))
        end

        # A single-use streaming body: Body.chunked takes anything answering #each, and what
        # XCUT-10 cares about is that `#replayable?` is false.
        def streaming_post(subject)
          safety_request(subject, "POST", subject.core::Body.chunked(::Enumerator.new do |y|
            y << "x"
          end),)
        end

        # rubocop:enable Metrics/AbcSize

        ROWS = [
          ["XCUT-8", "the status-to-exception factory refuses a non-error status",
           :error_factory_refuses_non_error_status,],
          ["XCUT-9", "the cause walk terminates on a cyclic chain, tracking by reference identity",
           :cycle_safe_cause_walk,],
          ["XCUT-10", "retry safety is decided from the request alone, uniformly",
           :retry_safety_is_uniform,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Classification
    end
  end
end
