# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"
require_relative "outcomes"

module Dexpace
  module Conformance
    module InvariantSuite
      # Group 7, redirect credential hygiene and the CSPRNG: XCUT-17 and XCUT-21.
      # A private_constant of InvariantSuite.
      module Credentials
        extend self

        # The three headers XCUT-17 (b) strips once a hop leaves the seed origin.
        ORIGIN_SCOPED = %w[authorization cookie proxy-authorization].freeze
        # The ORIGINAL seed origin every hop is judged against, never the previous hop's.
        SEED = "https://a.example/one"
        # XCUT-21's floor: ">= 128 bits for the Digest cnonce".
        ENTROPY_BYTES = 16
        # The two parameter kinds a `cnonce_source:` keyword can take.
        KEYWORD_KINDS = %i[key keyreq].freeze
        # How many drawn bytes are probed for reaching the rendering; a cnonce is far shorter.
        MAX_PROBED = 64

        # Each assertion below is one requirement's CLAUSES, and each clause is one Check, so the
        # metric is counting the requirement's own size. Splitting by count would split by
        # arithmetic rather than by behaviour -- which is .rubocop.yml's own recorded argument for
        # turning Minitest/MultipleAssertions off, applied to the assertions that mirror them.
        # XCUT-17, all four clauses, because a port can satisfy any three.
        def redirect_credential_hygiene(subject)
          subject.probe!(:Redirect, "6b's redirect step")
          same = subject.redirect_hop(from: SEED, to: "https://a.example/two",
                                      headers: { "authorization" => ["Bearer t"],
                                                 "cookie" => ["s=1"], },)
          Check.that(same.headers["authorization"].nil?,
                     "Authorization survived a SAME-ORIGIN re-issue (clause a)",
                     expected: nil, actual: same.headers["authorization"], ids: ["XCUT-17"],)
          check_cross_origin(subject)
          check_userinfo(subject)
          check_downgrade(subject)
        end

        # XCUT-17 clause (b).
        # @return [void]
        def check_cross_origin(subject)
          cross = subject.redirect_hop(from: SEED, to: "https://b.example/two",
                                       headers: { "authorization" => ["Bearer t"],
                                                  "cookie" => ["s=1"],
                                                  "proxy-authorization" => ["Basic x"], },)
          ORIGIN_SCOPED.each do |name|
            Check.that(cross.headers[name].nil?,
                       "#{name} survived a CROSS-ORIGIN re-issue (clause b)",
                       expected: nil, actual: cross.headers[name], ids: ["XCUT-17"],)
          end
        end

        # XCUT-17 clause (c).
        # @return [nil]
        def check_userinfo(subject)
          hop = subject.redirect_hop(from: SEED, to: "https://user:pw@a.example/two", headers: {})

          Check.that(!hop.url.to_s.include?("user:pw"),
                     "userinfo in the Location survived the re-issue (clause c)",
                     expected: "no userinfo", actual: hop.url.to_s, ids: ["XCUT-17"],)
        end

        # XCUT-17 clause (d).
        # @return [nil]
        def check_downgrade(subject)
          refused = Outcomes.refused?(lambda {
            subject.redirect_hop(from: SEED, to: "http://a.example/two", headers: {})
          })

          Check.that(refused,
                     "an HTTPS-to-HTTP downgrade was followed without opt-in (clause d)",
                     expected: "rejected", actual: "followed", ids: ["XCUT-17"],)
        end

        # XCUT-21: ">= 128 bits from a cryptographically-strong PRNG, NEVER a non-cryptographic
        # RNG." Two observations and no character count -- a character count called a 128-bit draw
        # truncated to eight characters conforming and a 22-character urlsafe_base64(16) not.
        #
        #   1. the handler takes an injectable cnonce_source:, so its randomness can be audited;
        #   2. bytes are DRAWN from the injected recorder and CARRIED into the rendered value --
        #      each drawn byte is flipped in turn and the rendering must change.
        def csprng_for_security_values(subject)
          subject.probe!(:Auth, "6c's authentication layer")
          handler = subject.core.const_get(:Auth).const_get(:DigestHandler)

          Check.that(injectable?(handler),
                     "the digest handler takes no injectable cnonce source, so its randomness " \
                     "source cannot be audited at all",
                     expected: "a cnonce_source: keyword", actual: "absent", ids: ["XCUT-21"],)
          check_entropy(subject)
        end

        def injectable?(handler)
          handler.instance_method(:initialize).parameters.any? do |(kind, name)|
            KEYWORD_KINDS.include?(kind) && name == :cnonce_source
          end
        end

        # XCUT-21's second and third observations: bytes drawn, and bytes carried.
        # @return [nil]
        def check_entropy(subject)
          base = Recorder.new
          rendered = subject.draw_cnonce(base).to_s
          Check.that(base.drawn.positive?,
                     "the handler drew no bytes from the injected source, so it uses some other " \
                     "randomness",
                     expected: "at least one draw", actual: 0, ids: ["XCUT-21"],)
          carried = (0...[base.drawn, MAX_PROBED].min).count do |index|
            subject.draw_cnonce(Recorder.new(index)).to_s != rendered
          end
          Check.that(carried >= ENTROPY_BYTES,
                     "the rendered cnonce carries fewer than 128 bits of the bytes drawn for it",
                     expected: ">= #{ENTROPY_BYTES} drawn bytes reach the cnonce",
                     actual: "#{carried} of #{base.drawn}", ids: ["XCUT-21"],)
        end

        # A Random::Formatter whose every draw is recorded. Formatter routes #hex,
        # #urlsafe_base64, #base64, #random_bytes, #uuid, #alphanumeric and #random_number through
        # #bytes, so defining #bytes records them all. Byte i is (0xA5 ^ i) & 0xFF, complemented
        # when i == flip, which is what makes "carried into the rendering" measurable per byte.
        class Recorder
          include ::Random::Formatter

          attr_reader :drawn

          def initialize(flip = nil)
            @flip = flip
            @drawn = 0
          end

          # @param count [Integer] how many bytes the subject asked for
          # @return [String] a deterministic run, one byte complemented when `flip` names it
          def bytes(count)
            chunk = ::Array.new(count) do |offset|
              byte = (0xA5 ^ (@drawn + offset)) & 0xFF
              @drawn + offset == @flip ? byte ^ 0xFF : byte
            end
            @drawn += count
            chunk.pack("C*")
          end
        end
        private_constant :Recorder

        ROWS = [
          ["XCUT-17", "redirect handling enforces credential hygiene",
           :redirect_credential_hygiene,],
          ["XCUT-21", "security-relevant randomness comes from a CSPRNG",
           :csprng_for_security_values,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Credentials
    end
  end
end
