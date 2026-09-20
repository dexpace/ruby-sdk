# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class Configuration
    # The well-known configuration key names (CFG-14): stable constants a caller passes to the
    # chain rather than restating the string. Five are CFG-14's own; two are the names phase
    # 5a's own wirings read, one is the name phase 5b's body-logging wiring reads, and one is the
    # name phase 8's transport adapters read. Nested
    # under Configuration because a key is a name the chain understands and reads wrongly as a
    # top-level Dexpace:: constant.
    #
    # Reopens `class Configuration`, which configuration.rb declares and requires this file from;
    # loading this file first would make the later declaration a superclass mismatch, so it
    # never appears in lib/dexpace.rb.
    module Keys
      # The retry-attempt cap RETRY-12 reads its default under. The NAME only: the 200 ms / x2 /
      # 8 s / 0.2 / 3-sends values are phase 6's.
      MAX_RETRY_ATTEMPTS = "MAX_RETRY_ATTEMPTS"

      # A PUBLISHED name a caller may pass -- never a default any resolver falls back to. OBS-35's
      # embedded MUST is "The SDK MUST NOT bake in a default config key name", so phase 5b's
      # log-level resolution takes its key as a required argument, and nothing in core reads this.
      LOG_LEVEL = "LOG_LEVEL"

      # The proxy URL CFG-24 reads second (the seven system-property names it and CFG-26 also
      # read are the resolver's private business, not keys).
      HTTP_PROXY = "HTTP_PROXY"
      # The proxy URL CFG-24 reads first, preferred over HTTP_PROXY.
      HTTPS_PROXY = "HTTPS_PROXY"
      # The comma-separated non-proxy host list CFG-26 reads when http.nonProxyHosts is unset.
      NO_PROXY = "NO_PROXY"

      # The configured ceiling behind Dexpace::IO.max_materialized_bytes -- the ceiling half of
      # the body-logging caps phase 3b postponed to phase 5.
      MAX_MATERIALIZED_BYTES = "MAX_MATERIALIZED_BYTES"

      # The cap ContextStore.default is built with -- the source phase 4a postponed to phase 5.
      MAX_TRACKED_CONTEXTS = "MAX_TRACKED_CONTEXTS"

      # The body-preview size the two logging wrappers are built with at the body level -- the
      # shared cap phase 3b postponed to phase 5, added by phase 5b in the change that reads it.
      # A published name a caller resolves and passes to Instrumentation::Step.build's
      # `preview_bytes:` (`configuration.integer(LOG_PREVIEW_BYTES, default: 8 * 1024)`, OBS-36's
      # reference default being the caller's choice); nothing in core reads it on its own.
      LOG_PREVIEW_BYTES = "LOG_PREVIEW_BYTES"

      # The per-call timeout budget a transport adapter reads for its CONFIGURED tier, added by
      # phase 8a in the change that reads it (its R3) and shared with phase 8c's adapter, so one
      # caller setting governs both transports. Read with `#duration`, whose grammar (CFG-7)
      # treats a bare number as MILLISECONDS: `REQUEST_TIMEOUT=30` is thirty milliseconds, and a
      # caller who means thirty seconds writes `30s` or `PT30S`. The precedent for a
      # transport-facing key nothing in core reads is HTTP_PROXY/HTTPS_PROXY/NO_PROXY above.
      REQUEST_TIMEOUT = "REQUEST_TIMEOUT"
    end
  end
end
