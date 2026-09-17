# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # The type-4 (random) UUID generator for request, trace and correlation IDs (CFG-32).
  #
  # **The output is NON-cryptographic and callers must treat it as such** -- CFG-32 says so in as
  # many words, and a reader will otherwise assume the opposite of anything called a UUID.
  # XCUT-21's security-relevant values (AUTH-20's nonces among them) come from a different code
  # path entirely, and keeping the two apart is phase 5's boundary 8: this file writes no
  # `require "securerandom"` and names no SecureRandom constant, which is checkable by text.
  #
  # **The generator is memoised in `Thread.current[:dexpace_prng]`, the carrier CLAUDE.md's
  # constraint list names as the WRONG one -- and this is the deliberate exception (P5-13).** That
  # rule is about the diagnostic context, where inheritance by a child fiber, a new Thread and an
  # Enumerator's internal fiber is the property wanted; docs/knowledge/notes/observability.md is
  # unamended and Fiber[] remains the only correct carrier there. Here the same inheritance is the
  # defect: verified on 3.2.11, 3.4.10 and 4.0.6, `Fiber[:k] = o` then
  # `Thread.new { Fiber[:k].equal?(o) }` is TRUE, so fiber storage hands the same generator object
  # to every thread the process later spawns -- exactly the "shared mutable state" CFG-32 forbids.
  # Thread.current[] is inherited by neither a child fiber nor a new Thread, so no two execution
  # contexts ever share one; the cost is one Random and one ~12 us seeding per fiber that
  # generates a UUID (R3), which is the number to re-measure if a fiber-scheduler adapter ever
  # reports this as hot.
  module UUID
    extend self

    # The slot the per-execution-context generator lives in. Fiber-local by construction.
    SLOT = :dexpace_prng
    private_constant :SLOT

    # A version 4 UUID as the canonical 8-4-4-4-12 lower-case hex string, frozen. The layout is
    # CFG-32's and verified across the range: 16 bytes from the memoised generator, byte 6 masked
    # to version 4, byte 8 masked to the IETF variant, `unpack1("H*")`, hyphenated. Random#bytes
    # returns an unfrozen BINARY String on every supported Ruby, so the two `setbyte`s need no
    # `dup` -- but the check is kept, because a future Ruby returning a frozen buffer would turn
    # this into a FrozenError at the first UUID.
    #
    # @return [String] a frozen v4 UUID; NOT suitable for secrets
    def generate
      prng = (::Thread.current[SLOT] ||= ::Random.new)
      raw = prng.bytes(16)
      raw = raw.dup if raw.frozen?
      raw.setbyte(6, (raw.getbyte(6) & 0x0f) | 0x40)
      raw.setbyte(8, (raw.getbyte(8) & 0x3f) | 0x80)
      hyphenate(raw.unpack1("H*"))
    end

    private

    def hyphenate(hex)
      "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}".freeze
    end
  end
end
