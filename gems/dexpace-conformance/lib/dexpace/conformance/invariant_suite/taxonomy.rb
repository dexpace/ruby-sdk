# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 2, the error taxonomy and the three retry classifiers: XCUT-4, XCUT-5, XCUT-6 and
      # XCUT-7. Three distinct objects, audited as three, because each answers a different
      # question and a port that folded them together would pass a single-object check.
      # A private_constant of InvariantSuite.
      module Taxonomy
        extend self

        # XCUT-5's classifier, stated as the requirement states it: 408, 429 and all 5xx EXCEPT
        # 501 and 505. 404 and 200 are the negative controls, 507 the 5xx a hard-coded
        # {500,502,503,504} list would miss.
        CLASSIFIER_CASES = { 408 => true, 429 => true, 500 => true, 502 => true, 503 => true,
                             504 => true, 507 => true, 501 => false, 505 => false, 404 => false,
                             400 => false, }.freeze
        # XCUT-7's two directions: a set admitting a status the classifier refuses, and one
        # refusing a status it admits; plus the default the requirement fixes.
        WIDENED = [404].freeze
        # A configured set that REFUSES a status the built-in classifier admits.
        NARROWED = [408].freeze
        # The default retryable-status set XCUT-7 fixes.
        DEFAULT_SET = [408, 429, 500, 502, 503, 504].freeze

        # Each assertion below is one requirement's CLAUSES, and each clause is one Check, so the
        # metric is counting the requirement's own size. Splitting by count would split by
        # arithmetic rather than by behaviour -- which is .rubocop.yml's own recorded argument for
        # turning Minitest/MultipleAssertions off, applied to the assertions that mirror them.
        # rubocop:disable Metrics/AbcSize
        # XCUT-4: "exactly two top-level branches" -- a protocol error carrying a fully-received
        # response, and a transport error carrying none and belonging to the runtime's I/O-error
        # family so existing I/O catch sites keep matching. The ancestry is the half a port gets
        # wrong: phase 1 made Dexpace::Error a MODULE precisely so a transport error could sit in
        # Ruby's IOError family and still be caught by a broad `rescue Dexpace::Error`.
        def two_branch_taxonomy(subject)
          subject.probe!(:TransportError, "8a's phase-level task")
          subject.probe!(:ProtocolError, "4b's recovery layer")
          klass = subject.core.const_get(:TransportError)

          Check.that(klass < ::IOError,
                     "a transport error is outside the runtime's I/O-error family",
                     expected: "< ::IOError", actual: klass.ancestors.take(4), ids: ["XCUT-4"],)
          error = klass.new("refused")
          Check.that(error.retryable? == true,
                     "a transport error does not report itself always-retryable",
                     expected: true, actual: error.retryable?, ids: ["XCUT-4"],)
          Check.that(error.is_a?(subject.core.const_get(:Error)),
                     "a transport error is outside the SDK's own rescue root, so a broad " \
                     "`rescue Dexpace::Error` stops matching it",
                     expected: true, actual: false, ids: ["XCUT-4"],)
          protocol = subject.core.const_get(:ProtocolError)
          Check.that(protocol.method_defined?(:response) && protocol.method_defined?(:status),
                     "a protocol error carries no fully-received response",
                     expected: "#response and #status", actual: "absent", ids: ["XCUT-4"],)
          Check.that(!(protocol <= ::IOError),
                     "the two branches are not distinct: a protocol error is also in the " \
                     "I/O-error family, so an I/O catch site swallows a protocol outcome",
                     expected: false, actual: true, ids: ["XCUT-4"],)
        end

        # XCUT-5: "computed ONCE at construction from a SINGLE shared status classifier, never
        # hardcoded per status subclass. That classifier MUST treat 408, 429, and all 5xx EXCEPT
        # 501 and 505 as retryable." The membership IS the requirement, so every case is walked.
        def one_shared_status_classifier(subject)
          subject.probe!(:Retryability, "5a's configuration layer")
          classifier = subject.core.const_get(:Retryability)
          wrong = CLASSIFIER_CASES.reject do |code, want|
            classifier.retryable_status?(code) == want
          end

          Check.that(wrong.empty?,
                     "the shared status classifier does not treat 408, 429 and every 5xx but 501 " \
                     "and 505 as retryable",
                     expected: CLASSIFIER_CASES, actual: wrong, ids: ["XCUT-5"],)
        end

        # XCUT-6: "a transport-family or CUSTOM error type that declares itself retryable via the
        # retryability capability MUST be able to participate WITHOUT EDITING the retry
        # classifier". So the double is a type the classifier has never heard of, and the query
        # must reach it through a cause chain as well as directly -- a capability read only off the
        # outermost error would miss every wrapped adapter failure.
        def open_capability_query(subject)
          subject.probe!(:Resilience, "6a's retry layer")
          policy = subject.core::Resilience.const_get(:Policy)
          yes = declaring(true)
          no = declaring(false)
          wrapped = begin
            begin
              raise yes
            rescue ::StandardError
              raise "wrapper"
            end
          rescue ::StandardError => error
            error
          end

          Check.that(policy.throwable_retryable?(yes),
                     "a custom error declaring itself retryable was not believed by the classifier",
                     expected: true, actual: false, ids: ["XCUT-6"],)
          Check.that(!policy.throwable_retryable?(no), "a custom error declaring itself NOT " \
                                                       "retryable was retried anyway",
                     expected: false, actual: true, ids: ["XCUT-6"],)
          Check.that(policy.throwable_retryable?(wrapped),
                     "the capability query reads only the outermost error, so a wrapped adapter " \
                     "failure never participates",
                     expected: true, actual: false, ids: ["XCUT-6"],)
        end

        # XCUT-7: "retry eligibility MUST be decided by a CONFIGURABLE retryable-status set, which
        # is AUTHORITATIVE: the set MAY widen the built-in classification or narrow it. The default
        # set is {408, 429, 500, 502, 503, 504}." Both directions, because a port that only ANDed
        # the set with the baked classifier would pass the narrowing half and fail the widening.
        def configurable_status_set_is_authoritative(subject)
          subject.probe!(:Resilience, "6a's retry layer")
          policy = subject.core::Resilience.const_get(:Policy)
          settings = subject.core::Resilience.const_get(:RetrySettings)
          default = settings.build.retryable_statuses.to_a.sort

          Check.that(default == DEFAULT_SET,
                     "the default retryable-status set is not the one XCUT-7 fixes",
                     expected: DEFAULT_SET, actual: default, ids: ["XCUT-7"],)
          Check.that(policy.retry_eligible?(404, set: WIDENED),
                     "a configured set could not WIDEN the built-in classification",
                     expected: true, actual: false, ids: ["XCUT-7"],)
          Check.that(!policy.retry_eligible?(503, set: NARROWED),
                     "a configured set could not NARROW the built-in classification",
                     expected: false, actual: true, ids: ["XCUT-7"],)
        end

        # An error type the classifier has never heard of, declaring its own retryability.
        # Built on the INSTANCE rather than as a class body, so the capability is the one the
        # query reads and nothing is declared on this module.
        def declaring(retryable)
          error = ::StandardError.new("custom")
          error.define_singleton_method(:retryable?) { retryable }
          error
        end

        # rubocop:enable Metrics/AbcSize

        ROWS = [
          ["XCUT-4", "the error taxonomy has two branches and a transport error is I/O-family",
           :two_branch_taxonomy,],
          ["XCUT-5", "one shared status classifier decides the baked retryability flag",
           :one_shared_status_classifier,],
          ["XCUT-6", "a custom error's retryability capability is queried, not its type",
           :open_capability_query,],
          ["XCUT-7", "the configured retryable-status set is authoritative and can widen or narrow",
           :configurable_status_set_is_authoritative,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Taxonomy
    end
  end
end
