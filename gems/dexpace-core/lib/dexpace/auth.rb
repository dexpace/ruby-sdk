# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # The authentication layer (product spec §11, AUTH-1–AUTH-38; design §6.3): the
  # descriptor/resolver model, the four credential types, the RFC 7235 challenge parser, the
  # Basic and Digest handlers, the composing chain, the key and bearer stampers, and the AUTH
  # pillar step on both runtimes.
  #
  # Everything here is a value, a pure function or an object a caller constructs and installs;
  # nothing is registered process-wide and nothing reads Dexpace.configuration (R11: the one
  # tunable, the Digest nonce store's cap, is a constructor keyword because the handler is
  # explicitly constructed and was never ambient). The layer depends on phases 0–5 only: it
  # reads the cross-origin marker phase 4c's cursor carries and never a header (AUTH-29, design
  # §10.15), gates every replay on phase 3b's Body#replayable? directly (AUTH-31), and takes the
  # per-nonce counter from phase 4a's BoundedMap by a bare name from a full-nesting body
  # (AUTH-19).
  module Auth
    # AUTH-8: what every credential's #to_s, #inspect and pretty-print show in place of its
    # secret. One marker for the four types, so a log line reads the same whichever credential
    # produced it. Distinct from the instrumentation redactor's `***`: that marks a redacted
    # header VALUE on the way into a log record; this marks a field the object itself refuses
    # to render, whatever asked.
    REDACTED = "[REDACTED]"
  end
end
