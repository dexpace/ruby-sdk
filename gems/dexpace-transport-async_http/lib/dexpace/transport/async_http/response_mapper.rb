# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # Step 15: the native response to a Dexpace::Response -- TRANSPORT-14's lenient inbound
      # copy, TRANSPORT-24's status mapping and TRANSPORT-27's two downgrades. The body handed to
      # ResponseBody is the native BODY, a `Protocol::HTTP::Body::Readable`, never the response:
      # `Protocol::HTTP::Response#read` is the WHOLE body joined into one String. Two clauses never
      # reach here on this adapter, both raised by protocol-http1 out of the read before a
      # response object exists: a malformed inbound header NAME (`Protocol::HTTP1::BadHeader`,
      # P8-38, the TRANSPORT-14 waiver) and a non-numeric Content-Length
      # (`Protocol::HTTP1::BadRequest`, the TRANSPORT-27 waiver) -- both wrap as retryable
      # transport failures. Since phase 10 Dexpace::Protocol admits HTTP/1.0 beside HTTP/1.1 and
      # HTTP/2 (HTTP-33) and Dexpace::Status every Integer code (HTTP-10, TRANSPORT-24), so an
      # `HTTP/1.0` head and a vendor `999` both map; a version the model does not know still
      # raises Dexpace::InvalidArgumentError here, after the head, with the native body closed by
      # the exchange's own release. A private_constant of AsyncHTTP.
      module ResponseMapper
        extend self

        # @param native [Protocol::HTTP::Response] the head, its body unread
        # @param request [Dexpace::Request] the request the response answers
        # @param logger [Dexpace::Instrumentation::Logger] where each malformed-header drop is
        #   logged at VERBOSE (TRANSPORT-14)
        # @param cancellation [Dexpace::Cancellation] the token the body is read under
        # @param head [Boolean] whether the request was a HEAD, whose response carries no body
        # @param on_release [#call, nil] handed to the ResponseBody; run once it is closed
        # @return [Dexpace::Response]
        def call(native, request:, logger:, cancellation:, head: false, on_release: nil)
          headers = inbound_headers(native, logger)
          body = body_for(native, head, cancellation: cancellation, on_release: on_release,
                                        media_type: media_type_for(headers), logger: logger,)
          on_release&.call if body.nil?
          ::Dexpace::Response.build(
            request: request, protocol: native.version.to_s, status: native.status,
            reason: reason_for(native), headers: headers, body: body,
          )
        end

        private

        # TRANSPORT-14: a name HeaderSyntax refuses or a value the inbound grammar refuses -- a
        # control byte -- is dropped, that header only, BEFORE it reaches Headers::Builder, which
        # would raise on exactly those bytes and fail the whole response; obs-text is an admitted
        # inbound byte and is kept. Names arrive as the protocol spelled them: preserved over
        # HTTP/1.1, lowercased over HTTP/2 (RFC 9113 §8.2.1), which is why every lookup folds.
        # Each drop is logged at VERBOSE by name -- never the value.
        def inbound_headers(native, logger)
          builder = ::Dexpace::Headers.inbound_builder
          native.headers.each do |name, value|
            next log_drop(logger, name) unless ::Dexpace::HeaderSyntax.valid_name?(name)
            next log_drop(logger, name) unless ::Dexpace::HeaderSyntax.valid_inbound_value?(value)

            builder.add(name, value)
          end
          builder.build
        end

        # A HEAD response, a 204 or anything else the library delivers with no body gets
        # `body: nil` and the native body, when one exists, is closed at once; otherwise a
        # ResponseBody over the native body, its length mapped from the library's nil to
        # BODY-35's -1 sentinel.
        def body_for(native, head, cancellation:, on_release:, media_type:, logger:)
          body = native.body
          if head || body.nil? || body.is_a?(::Protocol::HTTP::Body::Head)
            ::Dexpace.close_quietly(body, logger: logger)
            return nil
          end

          ResponseBody.new(native: body, media_type: media_type, content_length: body.length || -1,
                           cancellation: cancellation, logger: logger, on_release: on_release,)
        end

        # An HTTP/1.1 response carries its status line's reason phrase; an HTTP/2 one has none
        # (RFC 9113 §8.3.2), and the protocol-neutral response class declares no reader for it.
        def reason_for(native)
          native.respond_to?(:reason) ? native.reason : nil
        end

        # TRANSPORT-27: MediaType.parse RAISES on a malformed value rather than returning nil, so
        # this rescue is what produces "downgraded to no media type"; the malformed value still
        # reaches the caller verbatim in Dexpace::Headers.
        def media_type_for(headers)
          raw = headers["content-type"]&.first
          return nil if raw.nil?

          ::Dexpace::MediaType.parse(raw)
        rescue ::Dexpace::InvalidArgumentError
          nil
        end

        def log_drop(logger, name)
          event = ::Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED
          ::Dexpace::Instrumentation.contain(logger, event: event) do
            logger.event(::Dexpace::Instrumentation::Severity::VERBOSE)
              .event(event)
              .field("header", name.to_s.b)
              .field("reason", "malformed inbound header (TRANSPORT-14)")
              .emit
          end
        end
      end

      private_constant :ResponseMapper
    end
  end
end
