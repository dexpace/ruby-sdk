# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 1, models and lifecycle: XCUT-15's immutability, XCUT-13's two clauses and
      # XCUT-22's ownership. A private_constant of InvariantSuite.
      module Models
        extend self

        # A close that takes longer than this has blocked rather than signalled and returned.
        CLOSE_BOUND_SECONDS = 0.5

        # XCUT-15: "a model MUST NOT retain an alias to externally-mutable state that a
        # post-construction mutation could use to alter it". The mutation is on the INNER array,
        # because phase 1 files Headers.build(values:, casing:) over a Hash of
        # String => Array[String] and a port that dup'd only the outer Hash would pass a
        # top-level check.
        def immutable_models(subject)
          subject.probe!(:Headers, "phase 1's domain model")
          live = { "accept" => ["text/plain"] }
          casing = { "accept" => "Accept" }
          model = subject.core.const_get(:Headers).build(values: live, casing: casing)
          live["accept"] << "application/json"
          live["x-added"] = ["v"]

          Check.that(model["accept"] == ["text/plain"] && model["x-added"].nil?,
                     "a model changed when a collection passed into its builder was mutated",
                     expected: ["text/plain"], actual: model["accept"], ids: ["XCUT-15"],)
        end

        # XCUT-13, clause 1: "close()/shutdown() MUST be idempotent (latched so repeats are
        # no-ops)". Counted AT THE RESOURCE, never inferred from close's return value -- phase 2's
        # Closeable#close answers nil on the winning and the losing call alike.
        def idempotent_close(subject)
          seam = subject.seam
          seam.close
          seam.close

          Check.that(seam.release_count == 1, "close ran its release more than once",
                     expected: 1, actual: seam.release_count, ids: ["XCUT-13"],)
        end

        # XCUT-13, clause 2: "and MUST NOT block on interrupt-sensitive waits". Bounded by elapsed
        # monotonic time, never by an interrupt -- §8.3 bans Timeout.timeout, Thread#raise and
        # Thread#kill outright. Both calls are timed, so a latch that blocks only on the LOSING
        # call is caught too.
        def non_blocking_close(subject)
          seam = subject.seam
          started = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          seam.close
          seam.close
          elapsed = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) - started

          Check.that(elapsed < CLOSE_BOUND_SECONDS,
                     "close blocked rather than signalling and returning",
                     expected: "< #{CLOSE_BOUND_SECONDS}s", actual: elapsed.round(3),
                     ids: ["XCUT-13"],)
        end

        # XCUT-22: "build a transport around a caller-supplied client, close the transport, then
        # reuse the client -> it still works." Both halves, and the second is INDEPENDENT of the
        # first: `Borrowed` is torn down by `#finish` as well as by `#close`, so a component that
        # never called `#close` while shutting the resource down another way passes the first Check
        # and fails the second. A double whose `usable?` were merely the negation of its `closed?`
        # would make this Check unfalsifiable -- measured, in review round 2, by replacing its
        # condition with a literal `true` and finding the whole suite still green.
        def only_closes_what_it_created(subject)
          borrowed = Borrowed.new
          seam = subject.seam(client: borrowed)
          seam.close

          Check.that(!borrowed.closed?, "the SDK closed a resource it did not create",
                     expected: false, actual: borrowed.closed?, ids: ["XCUT-22"],)
          Check.that(borrowed.usable?, "a caller-supplied resource stopped working after the " \
                                       "SDK component that borrowed it was closed",
                     expected: true, actual: borrowed.usable?, ids: ["XCUT-22"],)
        end

        # The caller-supplied resource XCUT-22 is about, with the two observations the requirement
        # names on two INDEPENDENT routes: it was not closed, and it still works.
        #
        # `#finish` is the second route, and it is what makes the second observation worth making:
        # a holder can shut a borrowed resource down without ever calling `#close` -- `Net::HTTP`
        # spells that teardown `#finish`, a pooled client spells it "retire", and an adapter that
        # tore down a caller's SOCKET rather than the caller's client would leave `closed?` false.
        # Deriving `usable?` from `@closed` alone would make the second Check the negation of the
        # first and it could then never fail on its own.
        class Borrowed
          def initialize
            @closed = false
            @torn = false
          end

          # @return [Boolean] the latch a holder flips when it closes what it borrowed
          def close = (@closed = true)
          def closed? = @closed

          # The adapter-side teardown reached WITHOUT going through `#close`.
          # @return [Boolean]
          def finish = (@torn = true)

          # "then reuse the client -> it still works", asked of the resource rather than derived
          # from the latch the first Check already reads.
          # @return [Boolean]
          def usable? = !(@closed || @torn)
        end
        private_constant :Borrowed

        ROWS = [
          ["XCUT-15", "public wire models retain no external-mutable alias", :immutable_models],
          ["XCUT-13", "close is latched so repeats are no-ops", :idempotent_close],
          ["XCUT-13", "close does not block on an interrupt-sensitive wait", :non_blocking_close],
          ["XCUT-22", "a caller-supplied resource survives the SDK's close",
           :only_closes_what_it_created,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Models
    end
  end
end
