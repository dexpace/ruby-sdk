# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../http/url"
require_relative "severity"
require_relative "keys"
require_relative "http_logging"
require_relative "preview"

module Dexpace
  module Instrumentation
    # OBS-17, OBS-36, OBS-39 and P5-34: the one writer of the request, response and failure
    # events, shared by Step and AsyncStep. Two steps sharing one redaction POLICY would satisfy
    # OBS-17's letter and drift the moment one grew a field the other lacked; two steps sharing
    # one emitter -- which owns every `logger.event(...)` call and every field key the two steps
    # write -- cannot. Every name it writes is a constant on Keys or Events, covered by the
    # surface manifest, which is what makes OBS-39's "stable and predictable" mechanised.
    #
    # It redacts nothing and gates nothing itself. `url.full` and the header keys are redacted
    # on the way into Event#field by the field's NAME (design §8.1), and so is OBS-18's decision
    # of which header NAMES are logged at all (P5-102): every header goes in under its prefix,
    # and the event -- through the LOGGER's redactor, the one policy of the path (P5-95) --
    # keeps an allow-listed value, marks a non-allow-listed one with the fixed REDACTED marker
    # or omits it, as the policy's boolean says (P5-35). So the names a step logs and the values
    # its events redact cannot come from two policies, and a caller writing a header field by
    # hand gets exactly what this writer gets; both of the boolean's modes are exercised through
    # here, so neither is surface nothing exercises.
    #
    # Every event is INFO except the failure event, which is ERROR; the level the step holds
    # decides whether these run at all, and this class never reads it for the two events -- only
    # for the previews, which exist at the body level alone (OBS-34).
    #
    # A private_constant (P2-15, P4-3): its contract is the two steps', asserted through them,
    # and it is no service core offers.
    class Emitter
      def initialize(logger:, level:)
        @logger = logger
        @level = level
      end

      # The `http.request` event: the method token, the URL (redacted at #field), the
      # allow-listed request headers, and the declared body length when it is known. No request
      # preview here, deliberately: RequestLoggingBody mirrors on WRITE, and the write happens
      # inside `cursor.call`, AFTER this event -- a preview read now is "" on every request. It
      # rides on the response and failure events instead, which is also where BODY-20 wants it.
      #
      # @param request [Dexpace::Request] the request as the step will send it
      # @return [nil]
      def request(request)
        event = @logger.event(Severity::INFO).event(Events::HTTP_REQUEST)
        event.field(Keys::HTTP_REQUEST_METHOD, request.method.to_s)
        event.field(Keys::URL_FULL, Dexpace::URL.external_form(request.url))
        headers(event, request.headers, Keys::HTTP_REQUEST_HEADER_PREFIX)
        declared_size(event, Keys::HTTP_REQUEST_BODY_SIZE, request.body)
        event.emit
      end

      # The `http.response` event on success: the status code, the duration off the monotonic
      # clock (CFG-16), the allow-listed response headers, and either the declared response length
      # (below the body level) or, at the body level, both previews with their sizes taken from
      # the CAPTURE (OBS-36: "Logged body-size/preview fields therefore describe the captured
      # preview, not necessarily the full body").
      #
      # @param request [Dexpace::Request] the request as sent, its body wrapped at the body level
      # @param response [Dexpace::Response] the response, its body wrapped at the body level
      # @param duration_ms [Float] milliseconds from the step's start to the response
      # @return [nil]
      def response(request, response, duration_ms)
        event = @logger.event(Severity::INFO).event(Events::HTTP_RESPONSE)
        event.field(Keys::HTTP_RESPONSE_STATUS_CODE, response.status.code)
        event.field(Keys::HTTP_RESPONSE_DURATION_MS, duration_ms)
        headers(event, response.headers, Keys::HTTP_RESPONSE_HEADER_PREFIX)
        if @level.at_least?(HTTPLogging::BODY)
          request_preview(event, request)
          preview(event, Keys::HTTP_RESPONSE_BODY_PREVIEW, Keys::HTTP_RESPONSE_BODY_SIZE,
                  response.body,)
        else
          declared_size(event, Keys::HTTP_RESPONSE_BODY_SIZE, response.body)
        end
        event.emit
      end

      # The `http.response` event on failure (OBS-39: the same name, with `error.type` and the
      # throwable as the cause), at ERROR. No response body and no response preview at any
      # level -- phase 4b's ProtocolError decision, confirmed and extended: an error body is the
      # payload most likely to carry a token. At the body level the REQUEST preview is attached,
      # which is BODY-20's own case, "the bytes mirrored up to the failure point, to aid diagnosis
      # of a failed request".
      #
      # @param request [Dexpace::Request] the request as sent
      # @param error [Exception] what failed the request
      # @param duration_ms [Float] milliseconds from the step's start to the failure
      # @return [nil]
      def failure(request, error, duration_ms)
        event = @logger.event(Severity::ERROR).event(Events::HTTP_RESPONSE)
        event.field(Keys::ERROR_TYPE, error_type(error))
        event.field(Keys::HTTP_RESPONSE_DURATION_MS, duration_ms)
        event.cause(error)
        request_preview(event, request) if @level.at_least?(HTTPLogging::BODY)
        event.emit
      end

      private

      def request_preview(event, request)
        preview(event, Keys::HTTP_REQUEST_BODY_PREVIEW, Keys::HTTP_REQUEST_BODY_SIZE, request.body)
      end

      # Every header, folded, under its prefix; Event#field gates the NAME (OBS-18: marker or
      # omission, per the policy) and redacts a URL-valued header's value (OBS-16, OBS-17) on the
      # way in, so nothing is decided here -- and nothing is joined here either: the value list
      # goes over AS the list, and the event joins the redacted values with ", ", the wire's own
      # combination rule, so each name is one field and a second `Location`'s userinfo meets the
      # redactor on its own rather than behind the first value's path (P5-108).
      def headers(event, headers, prefix)
        headers.names.each do |name|
          event.field("#{prefix}#{name.downcase}", headers[name] || [])
        end
      end

      # The declared content length, only when known: BODY-35 fixes the unknown sentinel at -1,
      # which is truthy, so a truthiness guard would log -1 for every chunked body.
      def declared_size(event, key, body)
        return if body.nil?

        length = body.content_length
        event.field(key, length) if length >= 0
      end

      # One preview and its size from whatever a logging wrapper mirrored (OBS-36, OBS-38). A
      # body that is not a wrapper captured nothing and gets no fields; a wrapper's #snapshot
      # triggers ResponseLoggingBody's lazy drain, whose over-cap regime replays the prefix and
      # continues from the live tail, so the caller still receives every byte. The size is the
      # capture's bytesize, never the declared length.
      def preview(event, preview_key, size_key, body)
        return unless body.respond_to?(:snapshot)

        captured = body.snapshot
        event.field(size_key, captured.bytesize)
        event.field(preview_key, Preview.render(captured, media_type: body.media_type))
      end

      # The nearest NAMED class in the error's ancestry: `Class.new(StandardError).name` is nil,
      # and an anonymous error class is what a test suite and a metaprogrammed adapter produce.
      def error_type(error)
        klass = error.class #: untyped
        klass = klass.superclass while klass.name.nil?
        klass.name
      end
    end
    private_constant :Emitter
  end
end
