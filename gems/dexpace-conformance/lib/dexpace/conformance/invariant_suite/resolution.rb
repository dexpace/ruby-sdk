# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 8, the credential cache and seam resolution: XCUT-12 and XCUT-23.
      # A private_constant of InvariantSuite.
      module Resolution
        extend self

        # How many threads race one credential cache, which is XCUT-12's single-flight shape.
        RACERS = 16
        # A bound on every join, so a stuck racer fails the assertion rather than hanging it.
        JOIN_SECONDS = 5.0
        # The explicit-install entry point XCUT-23's message must name to be actionable.
        INSTALLER = "Dexpace::Conformance probe #install"

        # Each assertion below is one requirement's CLAUSES, and each clause is one Check, so the
        # metric is counting the requirement's own size. Splitting by count would split by
        # arithmetic rather than by behaviour -- which is .rubocop.yml's own recorded argument for
        # turning Minitest/MultipleAssertions off, applied to the assertions that mirror them.
        # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
        # XCUT-12 (SHOULD): "refresh SHOULD be single-flight -- only ONE concurrent caller fetches
        # an expiring token while the others reuse the result. Any lock guarding the refresh MUST
        # be scoped to that cache so it never serializes UNRELATED in-flight requests; holding
        # that scoped lock across the (possibly blocking) token fetch is acceptable and intended."
        #
        # N threads race one stamper over an expiring token and exactly one fetch must happen. The
        # THREAD form only: the fiber-scheduler form needs a credential path running under a
        # reactor, a composition no first-party suite assembles, and is phase 10's judgement.
        def single_flight_credential_cache(subject)
          subject.probe!(:Auth, "6c's authentication layer")
          provider = CountingProvider.new(subject.core::Auth::BearerToken)
          stamper = subject.core::Auth::BearerStamper.new(provider: provider)
          request = blank_request(subject)
          stamped = ::Thread::Queue.new
          racers = ::Array.new(RACERS) { ::Thread.new { stamped << stamper.call(request) } }
          # Every racer must be INSIDE the refresh before the gate opens, or the first thread
          # finishes alone and the other fifteen take the cached-token path without ever racing.
          # Measured: with the gate released immediately, a stamper that fetches per caller passed.
          # Under a conforming stamper one racer parks in #fetch and fifteen park on the
          # credential's lock; under a non-conforming one all sixteen park in #fetch. Both are
          # "sleep", so the barrier is the same for either and decides nothing by itself.
          all_parked = all_parked?(racers)
          provider.release
          racers.each { |thread| thread.join(JOIN_SECONDS) }

          Check.that(all_parked,
                     "not every concurrent caller reached the refresh before the fetch was " \
                     "released, so this assertion could not have discriminated",
                     expected: RACERS, actual: "some finished early", ids: ["XCUT-12"],)
          Check.that(provider.fetches == 1,
                     "a token refresh was not single-flight: every concurrent caller fetched",
                     expected: 1, actual: provider.fetches, ids: ["XCUT-12"],)
          Check.that(stamped.size == RACERS,
                     "not every concurrent caller was stamped from the one coalesced fetch",
                     expected: RACERS, actual: stamped.size, ids: ["XCUT-12"],)
        end

        # A provider that counts its fetches and parks until released, so "exactly one fetch" is a
        # measurement rather than a race that usually passes. 6c's contract is `#fetch`, never a
        # lambda: AUTH-11 refuses a provider that does not answer it.
        class CountingProvider
          def initialize(token_type)
            @token_type = token_type
            @gate = ::Thread::Queue.new
            @fetches = 0
            @lock = ::Thread::Mutex.new
          end

          # @return [void] lets every parked fetch return
          def release = @gate.close

          # @return [Integer] how many fetches actually reached the provider
          def fetches = @lock.synchronize { @fetches }

          # 6c's provider contract is `#fetch` and never a lambda, which AUTH-11 refuses.
          # @return [untyped] one bearer token, once the gate opens
          def fetch
            @lock.synchronize { @fetches += 1 }
            @gate.pop
            @token_type.build(token: "single-flight")
          end
        end
        private_constant :CountingProvider

        # XCUT-23: "an explicit install ALWAYS WINS; otherwise the implementation is
        # auto-discovered; and the presence of ZERO or MULTIPLE candidates with no explicit
        # selection MUST FAIL LOUDLY with an ACTIONABLE error rather than silently pick one or
        # no-op."
        #
        # Three ordered rules, and the ORDERING is the content: a port that fails loudly on
        # ambiguity but lets discovery beat an explicit install satisfies two of three. "Loud" is
        # checked for its own reason too -- the error must name the explicit-install entry point,
        # which is what makes it actionable rather than merely raised. Every construction and
        # registration sits OUTSIDE the rescues, so a call-shape mistake is :error and can never
        # masquerade as a loud failure.
        def seam_resolution_is_deterministic(subject)
          subject.probe!(:Registry, "phase 2's Dexpace::Registry")
          registry = subject.core.const_get(:Registry)
          fresh = lambda do
            registry.new(seam: "conformance-probe", installer: INSTALLER,
                         conforms: ->(_provider) { true },)
          end
          major, minor = subject.core.const_get(:VERSION).to_s.split(".")
          core = "~> #{major}.#{minor}"

          empty = failure_of(fresh.call)
          Check.that(!empty.nil? && empty.message.include?(INSTALLER),
                     "resolving with no candidate did not fail loudly with an actionable error " \
                     "naming the explicit-install entry point",
                     expected: "an error naming #{INSTALLER}", actual: empty&.message,
                     ids: ["XCUT-23"],)

          ambiguous = fresh.call
          ambiguous.register(:a, -> { :a }, core: core)
          ambiguous.register(:b, -> { :b }, core: core)
          outcome = failure_of(ambiguous)
          Check.that(!outcome.nil? && outcome.message.include?(INSTALLER),
                     "two registered candidates with no explicit install did not fail loudly",
                     expected: "an error naming #{INSTALLER}", actual: outcome&.message,
                     ids: ["XCUT-23"],)

          explicit = fresh.call
          explicit.register(:discovered, -> { :discovered }, core: core)
          explicit.install(:installed)
          Check.that(explicit.resolve == :installed,
                     "an auto-discovered implementation beat an explicit install",
                     expected: :installed, actual: explicit.resolve, ids: ["XCUT-23"],)

          discovered = fresh.call
          discovered.register(:only, -> { :only }, core: core)
          Check.that(discovered.resolve == :only,
                     "a single registered candidate was not auto-discovered",
                     expected: :only, actual: discovered.resolve, ids: ["XCUT-23"],)
        end

        # Spins until every thread is blocked, bounded. `Thread#status` is "sleep" for a thread
        # parked on a queue or a mutex on every supported interpreter, and falsy for one that has
        # already finished -- which is not parked, and makes this answer false rather than hang.
        #
        # @return [Boolean] whether all of them were parked at once inside the bound
        def all_parked?(threads, bound: JOIN_SECONDS)
          deadline = ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) + bound
          until ::Process.clock_gettime(::Process::CLOCK_MONOTONIC) > deadline
            return true if threads.all? { |thread| thread.status == "sleep" }
            break if threads.any? { |thread| !thread.status }

            ::Thread.pass
          end
          false
        end

        # @return [StandardError, nil] what resolving raised, or nil when it resolved
        def failure_of(registry)
          registry.resolve
          nil
        rescue ::StandardError => error
          error
        end

        # @return [untyped] a minimal request for the stamper to stamp
        def blank_request(subject)
          subject.core::Request.build(method: subject.core::Method::GET,
                                      url: "https://a.example/x",
                                      headers: subject.core::Headers::EMPTY,)
        end

        # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

        ROWS = [
          ["XCUT-12", "a credential cache's refresh is single-flight",
           :single_flight_credential_cache,],
          ["XCUT-23", "a single-implementation seam resolves deterministically",
           :seam_resolution_is_deterministic,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Resolution
    end
  end
end
