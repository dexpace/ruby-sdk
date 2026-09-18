# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  class Configuration
    # The well-known configuration key names (CFG-14): stable constants a caller passes to the
    # chain rather than restating the string. Five are CFG-14's own; two are the names this
    # phase's own wirings read. Nested under Configuration because a key is a name the chain
    # understands and reads wrongly as a top-level Dexpace:: constant.
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
    end
  end
end
