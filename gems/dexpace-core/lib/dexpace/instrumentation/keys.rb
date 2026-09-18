# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-39: the field keys the logging half emits, as frozen String constants. "The set of
    # emitted structured event names and field keys MUST be stable and predictable", and design
    # §8.1 makes that mechanical rather than promised: every constant here is a row in the
    # runtime surface manifest, so a renamed or dropped key fails `gates:surface_snapshot`.
    # Sixteen: OBS-39's named minimum, the reserved `event` key OBS-4 fixes, the `cause` the
    # failure event attaches, the `message` a configuration diagnostic carries, and the two
    # OTel instrument names the step records under (R11 moved them here from 5c; OBS-32's
    # units, descriptions and attribute sets stay post-v1).
    module Keys
      # OBS-4's reserved categorisation key; Event#event(name) writes it, exactly once.
      EVENT = "event"
      # The request's method token.
      HTTP_REQUEST_METHOD = "http.request.method"
      # The request URL, ALWAYS the redacted form: Event#field routes this key through
      # Redactor#url structurally, whoever the caller is (OBS-39's last sentence).
      URL_FULL = "url.full"
      # The response status code, an Integer.
      HTTP_RESPONSE_STATUS_CODE = "http.response.status_code"
      # Milliseconds from the step's first line to the response, off Clock#monotonic and never
      # Clock#now (CFG-16).
      HTTP_RESPONSE_DURATION_MS = "http.response.duration_ms"
      # The request body's declared length at the headers level, and the captured preview's
      # size at the body level (OBS-36).
      HTTP_REQUEST_BODY_SIZE = "http.request.body.size"
      # The response body's declared length at the headers level, and the captured preview's
      # size at the body level (OBS-36).
      HTTP_RESPONSE_BODY_SIZE = "http.response.body.size"
      # The captured request body preview, rendered by Preview (OBS-36, OBS-38); body level only.
      HTTP_REQUEST_BODY_PREVIEW = "http.request.body.preview"
      # The captured response body preview, rendered by Preview (OBS-36, OBS-38); body level only.
      HTTP_RESPONSE_BODY_PREVIEW = "http.response.body.preview"
      # The prefix a request header's folded name follows; Event#field redacts a URL-valued
      # header under it through Redactor#header_value (OBS-16, OBS-17).
      HTTP_REQUEST_HEADER_PREFIX = "http.request.header."
      # The prefix a response header's folded name follows, redacted the same way.
      HTTP_RESPONSE_HEADER_PREFIX = "http.response.header."
      # The failure event's error class name (OBS-39).
      ERROR_TYPE = "error.type"
      # OBS-39's "the throwable cause attached": Event#cause is the only writer and Render
      # shapes the value as `SimpleClassName: message`.
      CAUSE = "cause"
      # The free-text line an http.instrumentation.config diagnostic carries beside the
      # Kernel#warn it accompanies (CFG-24, CFG-25; P5-8).
      MESSAGE = "message"
      # The request counter's instrument name, OBS-32's recommended spelling (OBS-34).
      INSTRUMENT_REQUEST_COUNT = "http.client.request.count"
      # The latency histogram's instrument name, OBS-32's recommended spelling (OBS-34).
      INSTRUMENT_REQUEST_DURATION = "http.client.request.duration"
    end

    # OBS-39 and OBS-20: the event names the logging half emits, as frozen String constants
    # covered by the surface manifest for the reason Keys gives. Two are the request cycle's;
    # the five diagnostics share OBS-20's `http.instrumentation.` prefix, derived from one
    # constant so a test can assert every diagnostic starts with it.
    module Events
      # The request event (OBS-39).
      HTTP_REQUEST = "http.request"
      # The response event, on success AND on failure: OBS-39 is explicit that "a failure emits
      # an 'http.response' event with 'error.type'", not a third name.
      HTTP_RESPONSE = "http.response"
      # OBS-20's diagnostic family prefix.
      INSTRUMENTATION_PREFIX = "http.instrumentation."
      # OBS-20's own case: a log-emission site raised, and Instrumentation.contain re-surfaced it.
      INSTRUMENTATION_LOG = "#{INSTRUMENTATION_PREFIX}log".freeze
      # Dexpace.close_quietly's second disposal route: a close failure with no primary to attach
      # it to (the route phase 2 postponed to this phase).
      INSTRUMENTATION_CLOSE = "#{INSTRUMENTATION_PREFIX}close".freeze
      # Hooks.notify's per-dropped-failure diagnostic, beside phase 4b's suppressed trail.
      INSTRUMENTATION_HOOK = "#{INSTRUMENTATION_PREFIX}hook".freeze
      # SEAM-25's lifecycle event on the first close of an owned executor: the NAME and field
      # shape ship here; the emission is phase 8b's, where the first owned executor exists. A
      # log-event name, not an OBS-28 tracer callback -- that vocabulary has no lifecycle
      # milestone of a resource, and a twelfth method would be one OBS-28 does not name.
      INSTRUMENTATION_SHUTDOWN = "#{INSTRUMENTATION_PREFIX}shutdown".freeze
      # CFG-24/CFG-25's proxy-configuration warning, emitted BESIDE 5a's Kernel#warn (P5-8).
      INSTRUMENTATION_CONFIG = "#{INSTRUMENTATION_PREFIX}config".freeze
    end
  end
end
