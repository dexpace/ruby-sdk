# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 4, bounded memory: XCUT-14's two clauses and XCUT-24's two. A private_constant of
      # InvariantSuite.
      module Memory
        extend self

        # The cap every bounded-map assertion builds its subject with.
        CAP = 8
        # The over-cap state a concurrent insert burst leaves, arranged without a thread.
        OVERSHOOT = 5
        # Far more insertions than the cap, which is XCUT-14's own conformance shape.
        BURST = CAP * 40
        # The byte cap a body log preview is built with.
        PREVIEW_BYTES = 64
        # The byte cap an error-body snapshot is taken under.
        SNAPSHOT_CAP = 100
        # A payload far past both caps, so a missing cap is visible in the result.
        PAYLOAD_BYTES = 5000

        # Each assertion below is one requirement's CLAUSES, and each clause is one Check, so the
        # metric is counting the requirement's own size. Splitting by count would split by
        # arithmetic rather than by behaviour -- which is .rubocop.yml's own recorded argument for
        # turning Minitest/MultipleAssertions off, applied to the assertions that mirror them.
        # rubocop:disable Metrics/AbcSize
        # XCUT-14's CAP clause: "insert far more than the cap of distinct keys; assert map size
        # never exceeds the cap." Single-threaded and DETERMINISTIC, reading the size after EVERY
        # insert -- a check that read it only at the end would pass an implementation that
        # overshoots and then trims.
        def bounded_maps(subject)
          map = subject.bounded_map(cap: CAP)
          sizes = ::Array.new(BURST) do |index|
            map.set("key-#{index}", index)
            map.size
          end

          Check.that(sizes.max <= CAP, "an insert burst pushed the map past its cap",
                     expected: "<= #{CAP}", actual: sizes.max, ids: ["XCUT-14"],)
        end

        # XCUT-14's DRAIN-TO-CAP clause: evict "using a loop (not a single pre-insert
        # check-then-evict), so a concurrent insert burst converges to the bound instead of
        # overshooting permanently."
        #
        # Decided behaviourally and deterministically: fill the BACKING STORE to cap + 5 -- the
        # state a concurrent overshoot leaves, arranged without a thread -- then perform ONE #set.
        # A drain loop ends at the cap; a check-then-evict ends at cap + 5, on every interpreter.
        # This assertion is the only line on that clause: a shape gate over the source caught 1 of
        # 3 non-conforming forms with a false positive, and is out of v1 for that reason.
        def bounded_map_drains(subject)
          map = subject.bounded_map(cap: CAP)
          store = subject.bounded_map_store(map)
          (CAP + OVERSHOOT).times { |index| store["overshoot-#{index}"] = index }
          before = map.size
          map.set("after-overshoot", 0)

          Check.that(before > CAP, "the store reader did not reach past the cap, so this " \
                                   "assertion could not have discriminated",
                     expected: "> #{CAP}", actual: before, ids: ["XCUT-14"],)
          Check.that(map.size <= CAP,
                     "one insert into an over-cap map evicted once instead of draining back to " \
                     "the cap",
                     expected: "<= #{CAP}", actual: map.size, ids: ["XCUT-14"],)
        end

        # XCUT-24: "diagnostic/preview reads of caller- or server-controlled payloads MUST be
        # byte-capped and SHOULD be non-consuming -- a preview MUST NOT materialize an unbounded
        # payload into memory and MUST NOT disturb the primary read path the consumer will use."
        #
        # Both subjects, because the two halves live in different objects: 4b's error-body
        # snapshot is the cap, 3b's logging tap is the non-consumption. A preview that capped but
        # drained would pass the first alone, which is the failure the second clause names.
        def capped_non_consuming_preview(subject)
          subject.probe!(:Body, "3b's body layer")
          subject.probe!(:ResponseLoggingBody, "3b's logging wrappers")
          snapshot = subject.core::Body.buffer_bounded(payload(subject), cap: SNAPSHOT_CAP)

          Check.that(snapshot.content_length <= SNAPSHOT_CAP,
                     "an error-body snapshot materialised an unbounded payload",
                     expected: "<= #{SNAPSHOT_CAP}", actual: snapshot.content_length,
                     ids: ["XCUT-24"],)
          tap = subject.core::ResponseLoggingBody.new(payload(subject),
                                                      preview_bytes: PREVIEW_BYTES,)
          through = tap.source.read(PAYLOAD_BYTES * 2).bytesize
          Check.that(tap.snapshot.bytesize <= PREVIEW_BYTES,
                     "a body log preview is not byte-capped",
                     expected: "<= #{PREVIEW_BYTES}", actual: tap.snapshot.bytesize,
                     ids: ["XCUT-24"],)
          Check.that(through == PAYLOAD_BYTES,
                     "the preview disturbed the primary read path: the consumer saw a short body",
                     expected: PAYLOAD_BYTES, actual: through, ids: ["XCUT-24"],)
        end

        # @return [untyped] a fresh single-use response body of PAYLOAD_BYTES
        def payload(subject)
          source = subject.core::IO::BufferedSource.of_bytes("a".b * PAYLOAD_BYTES)
          subject.core::ResponseBody.new(source: source, content_length: PAYLOAD_BYTES,
                                         media_type: subject.core::MediaType.parse("text/plain"),)
        end

        # rubocop:enable Metrics/AbcSize

        ROWS = [
          ["XCUT-14", "a caller-keyed map never exceeds its cap", :bounded_maps],
          ["XCUT-14", "one insert drains an over-cap map back to its cap", :bounded_map_drains],
          ["XCUT-24", "a diagnostic preview is byte-capped and leaves the primary read intact",
           :capped_non_consuming_preview,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Memory
    end
  end
end
