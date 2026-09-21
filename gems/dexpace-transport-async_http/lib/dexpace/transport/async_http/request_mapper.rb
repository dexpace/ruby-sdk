# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # Steps 4 to 9 of the dispatch path as one function returning a `Protocol::HTTP::Request`:
      # the wire-boundary re-validation, the framing-header drop (TRANSPORT-11), the wire-grammar
      # drop (TRANSPORT-12, TRANSPORT-13, P8-40), Content-Type authority (TRANSPORT-10) and the
      # native request. The only place in this gem that touches Dexpace::HeaderSyntax, the only
      # place that reads FRAMING_HEADERS, and the only place that constructs a native request.
      # Runs on the caller's own fiber before any task exists, so a raise here reaches the
      # future without a reactor turn. A private_constant of AsyncHTTP.
      module RequestMapper
        extend self

        # @param request [Dexpace::Request] the request to send, or anything duck-typed like one
        # @param logger [Dexpace::Instrumentation::Logger] where each framing drop is logged at
        #   VERBOSE
        # @param drop_policy [DropPolicy] how a wire-grammar drop is logged
        # @return [Protocol::HTTP::Request]
        # @raise [Dexpace::InvalidArgumentError] when an outbound header name or value fails the
        #   wire-boundary re-validation (HTTP-17, HTTP-18)
        def call(request, logger:, drop_policy:)
          Endpoints.screen!(request.url)
          revalidate!(request)

          fields = ::Protocol::HTTP::Headers.new
          content_type = copy_headers(request, fields, logger, drop_policy)
          set_content_type(request, fields) unless content_type
          # The screen above admitted http and https alone, and URL.parse! builds the class from
          # the scheme, so the URL is a URI::HTTP and #request_uri is its own.
          url = request.url #: URI::HTTP
          ::Protocol::HTTP::Request.new(
            url.scheme, authority_for(url), request.method.token, url.request_uri, nil, fields,
            body_for(request),
          )
        end

        private

        # The wire-boundary re-validation phase 1 postponed to the adapters (HTTP-17, HTTP-18,
        # XCUT-18): every outbound name and value is checked again immediately before dispatch,
        # BEFORE anything is copied, because HTTP-2's constructor privacy is bypassable and a
        # duck-typed impostor can reach this code with no Dexpace validation ever having run. On
        # the HTTP/2 path this is the ONLY validation between the model and the wire:
        # protocol-http2 transmits a CRLF-bearing value verbatim (the design's verified fact 4).
        def revalidate!(request)
          request.headers.each_entry do |name, value|
            ::Dexpace::HeaderSyntax.validate_name!(name)
            ::Dexpace::HeaderSyntax.validate_outbound_value!(value, name: name)
          end
        end

        # Three fates for a caller's header, decided on the folded name and then on the RFC 7230
        # token grammar: a framing header is dropped and logged at VERBOSE (TRANSPORT-11); a name
        # the token grammar refuses is dropped and reported through the policy (TRANSPORT-12/13);
        # everything else is copied as spelled. The token predicate is applied on BOTH protocols
        # (P8-40): HTTP-17 admits seventeen bytes the tchar set refuses (`"(),/:;<=>?@[\]{}`),
        # protocol-http1 raises on such a name only AFTER the request line and `host:` are on the
        # socket, and protocol-http2 transmits it lowercased and unvalidated -- so the drop is a
        # pre-dispatch predicate, never a rescue, and one request produces one header set whatever
        # ALPN negotiated. `HeaderSyntax.token?` is byte-exact and total over invalid UTF-8, which
        # a regexp is not. Returns whether the caller set a Content-Type of their own.
        def copy_headers(request, fields, logger, drop_policy)
          content_type = false
          request.headers.each_entry do |name, value|
            folded = ::Dexpace::HeaderName.of(name).folded
            if FRAMING_HEADERS.include?(folded)
              log_framing_drop(logger, name)
            elsif !::Dexpace::HeaderSyntax.token?(name)
              drop_policy.report(logger, name, "not an RFC 7230 token (TRANSPORT-12)")
            else
              content_type ||= folded == "content-type"
              fields.add(name, value)
            end
          end
          content_type
        end

        # TRANSPORT-10: the caller's explicit header wins (already copied, matched folded); failing
        # that the body's own media type. No default is invented for a body with no media type:
        # async-http stamps none itself, and the four-member Request is the whole truth about what
        # goes out (HTTP-6) -- the one departure from dexpace-transport-net_http, whose
        # octet-stream default exists to pre-empt Net::HTTP's form-type fallback.
        def set_content_type(request, fields)
          media = request.body&.media_type
          fields.add("content-type", media.render) if media
        end

        # The body as the library pulls it, or nil: a body-less request goes out as a zero-length
        # body with `content-length: 0`, which async-http writes itself (TRANSPORT-26). The framing
        # is the library's, derived from RequestBody#length, and never copied from a header.
        def body_for(request)
          body = request.body
          return nil if body.nil? || request.method.body_forbidden?

          RequestBody.new(body)
        end

        # `host:` is written by async-http from the request's authority and a caller's value would
        # be APPENDED beside it (fact 5), which is why `host` is in FRAMING_HEADERS. The
        # scheme-default port is elided as HTTP wants it.
        def authority_for(url)
          port = url.port
          port && port != url.default_port ? "#{url.host}:#{port}" : url.host.to_s
        end

        # TRANSPORT-11's SHOULD: each drop at VERBOSE through the one containment helper (OBS-20),
        # under the shared transport event with the shared field pair, so one conformance
        # assertion reads a drop record from either adapter. Never through DropPolicy.
        def log_framing_drop(logger, name)
          event = ::Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED
          ::Dexpace::Instrumentation.contain(logger, event: event) do
            logger.event(::Dexpace::Instrumentation::Severity::VERBOSE)
              .event(event)
              .field("header", name.to_s)
              .field("reason", "transport framing header (TRANSPORT-11)")
              .emit
          end
        end
      end

      private_constant :RequestMapper
    end
  end
end
