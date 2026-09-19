# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Redirect
    # REDIR-28's event names, as frozen String constants: the redirect layer's own vocabulary,
    # filed beside the step that emits it rather than in Instrumentation::Events (which holds
    # the request cycle's two names, the `http.instrumentation.` diagnostics and 6c's one
    # auth diagnostic) for the reason R8 gives -- five names and four keys are a subsystem's
    # catalogue, and 5b's reserved-key table is deliberately not reused for them. Every
    # constant here is a row in the runtime surface manifest, so a renamed or dropped name
    # fails gates:surface_snapshot (OBS-39's stability, by the same mechanism 5b uses).
    #
    # REDIR-15 has TWO observable outcomes and they are two names: the rejection is emitted and
    # then raised as SchemeDowngradeError, the opt-in is emitted and followed. Logging
    # "rejected" for a downgrade that went through would say the opposite of what happened.
    module Events
      # One hop followed: the from and to URLs (redacted), the status and the count so far.
      HOP_FOLLOWED = "http.redirect.hop"
      # REDIR-16: the resolved target was already visited; the current response is returned.
      LOOP_DETECTED = "http.redirect.loop_detected"
      # REDIR-15: an HTTPS -> HTTP hop refused by default; SchemeDowngradeError follows it.
      SCHEME_DOWNGRADE_REJECTED = "http.redirect.scheme_downgrade_rejected"
      # REDIR-15: an HTTPS -> HTTP hop the caller opted into -- the observable surfacing the
      # opt-in requires.
      SCHEME_DOWNGRADE_PERMITTED = "http.redirect.scheme_downgrade_permitted"
      # REDIR-18: a Location that failed to parse, to resolve, or to name a dispatchable
      # target; the current response is returned unfollowed.
      LOCATION_MALFORMED = "http.redirect.location_malformed"
    end

    # REDIR-28's field keys. The two URL-valued keys are ALWAYS written through the logger's
    # redactor at the emission site, by name, because they are not Instrumentation::Keys::URL_FULL
    # and 5b's structural redaction does not reach them (R8); the raw-Location key is the one
    # value REDIR-28 says must NOT be redacted. The redirect response's status is logged under
    # 5b's own Instrumentation::Keys::HTTP_RESPONSE_STATUS_CODE rather than a parallel name.
    module Keys
      # The current hop's request URL, redacted.
      FROM_URL = "http.redirect.from_url"
      # The resolved target, redacted.
      TO_URL = "http.redirect.to_url"
      # Redirects followed before this hop, an Integer.
      REDIRECT_COUNT = "http.redirect.count"
      # The Location header value exactly as received -- raw, because it failed to parse and
      # therefore cannot be redacted; a sink receiving credential-bearing malformed values is
      # the porter's concern REDIR-28's last clause names.
      LOCATION_RAW = "http.redirect.location_raw"
    end
  end
end
