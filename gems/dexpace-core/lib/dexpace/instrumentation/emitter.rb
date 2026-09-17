# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../http/url"
require_relative "severity"
require_relative "keys"
require_relative "http_logging"
require_relative "preview"
require_relative "redactor"

module Dexpace
  module Instrumentation
    # OBS-17, OBS-36, OBS-39 and P5-34: the one writer of the request, response and failure
    # events, shared by Step and AsyncStep. Two steps sharing one redaction POLICY would satisfy
    # OBS-17's letter and drift the moment one grew a field the other lacked; two steps sharing
    # one emitter -- which owns every `logger.event(...)` call and every field key the two steps
    # write -- cannot. Every name it writes is a constant on Keys or Events, covered by the
    # surface manifest, which is what makes OBS-39's "stable and predictable" mechanised.
    #
    # It redacts nothing itself. `url.full` and the header keys are redacted on the way into
    # Event#field by the field's NAME (design §8.1), so the request URL and every header value
    # pass through here raw and come out redacted whoever the caller is. What this class does
    # decide is which header NAMES are logged at all (OBS-18): the allow-list of the LOGGER's
    # redactor gates them -- the one policy of the path, read from the logger rather than
    # carried separately (P5-95), so the names a step logs and the values its events redact
    # cannot come from two policies -- and a name outside it is emitted with the fixed REDACTED
    # marker or omitted, as the policy's boolean says (P5-35); both modes have a caller here, so
    # neither is surface nothing exercises.
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
        @redactor = logger.redactor
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

      # OBS-18 gates NAMES first, against the folded name: an allow-listed header's value is
      # logged (and, for a URL-valued name, redacted at #field by the prefix, OBS-17); any other
      # header is emitted with the marker or omitted per the policy. Multiple values of one name
      # are joined with ", ", the wire's own combination rule, so each name is one field.
      def headers(event, headers, prefix)
        omit = @redactor.policy.omit_disallowed_headers
        headers.names.each do |name|
          folded = name.downcase
          key = "#{prefix}#{folded}"
          if @redactor.header_name?(folded)
            values = headers[name] || []
            event.field(key, values.size == 1 ? values.first : values.join(", "))
          elsif !omit
            event.field(key, Redactor::REDACTED_HEADER)
          end
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
