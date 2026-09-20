# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module NetHTTP
      # Takes the native head off the pump and returns a Dexpace::Response (TRANSPORT-14,
      # TRANSPORT-24, TRANSPORT-27). R4: this file never calls `res.content_length` and never lets
      # `read_body` call it either -- the length is parsed from the RAW header text, and an
      # unparseable one is deleted from the native response before the pump reads the body, so
      # connection-close framing takes over instead of Net::HTTPResponse#content_length raising
      # Net::HTTPHeaderSyntaxError. Headers come from `#to_hash` and nothing else: `#[]` joins
      # with ", " and `#each_capitalized` re-cases, both of which would corrupt a multi-valued
      # Set-Cookie. Dexpace::Protocol admits HTTP/1.1 and HTTP/2 only (HTTP-33), so an HTTP/1.0
      # response raises Dexpace::InvalidArgumentError here; no TRANSPORT ID asks for 1.0 and the
      # gap is phase 1's to widen. A private_constant of NetHTTP.
      module ResponseMapper
        extend self

        # R4: anchored and character-class-only, so it cannot backtrack; spelled as core spells
        # every pattern a wire value reaches (`PacingParsers`, `P6-61`) -- `Regexp.new` with a
        # per-pattern timeout, never a literal, and a bounded run, so no header can hand `to_i` an
        # unbounded digit string. `Integer("-4", exception: false)` would answer -4 and collide
        # with the unknown-length sentinel; this admits one to fifteen digits and nothing else,
        # and a longer run is the unknown-length sentinel like any other value it refuses.
        LENGTH = ::Regexp.new('\A[0-9]{1,15}\z', timeout: 1.0).freeze
        private_constant :LENGTH

        # @param request [Dexpace::Request] the request the response answers
        # @param native [Net::HTTPResponse] the head, delivered by the pump before any body read
        # @param pump [#readpartial, #close] the body source; closed here when there is no body
        # @param logger [Dexpace::Instrumentation::Logger] where each malformed-header drop is
        #   logged at VERBOSE (TRANSPORT-14)
        # @param head [Boolean] whether the request was a HEAD, whose response carries no body
        #   whatever its status class says
        # @return [Dexpace::Response]
        def build(request:, native:, pump:, logger: ::Dexpace::Instrumentation::Logger::NULL,
                  head: false)
          # ORDER IS LOAD-BEARING: the headers are copied into Dexpace::Headers FIRST, so the
          # caller keeps the Content-Length the server actually sent; parse_length! may then
          # delete it from the NATIVE response, which is an instruction to read_body's framing and
          # not a rewrite of the response.
          headers = filter_headers(native, logger)
          body = body_for(native, pump, head)
          ::Dexpace::Response.build(
            request: request, protocol: "HTTP/#{native.http_version}", status: native.code.to_i,
            reason: native.message, headers: headers, body: body,
          )
        end

        private

        # A 204, a 304 or a HEAD response -- anything for which Net::HTTP will read no body --
        # gets `body: nil` and the pump is closed at once, because a ResponseBody over a stream
        # that will never yield is a resource with no reader.
        def body_for(native, pump, head)
          if head || !native.class.body_permitted?
            ::Dexpace.close_quietly(pump)
            return nil
          end

          content_length = parse_length!(native)
          ::Dexpace::ResponseBody.new(source: ::Dexpace::IO::BufferedSource.wrapping(pump),
                                      media_type: parse_media_type(native),
                                      content_length: content_length,)
        end

        # R4: the raw header, or -1 for absent, non-numeric, negative or multi-valued -- and in
        # the -1 case the header is deleted from the NATIVE response so read_body finds no length
        # and no chunked encoding and falls through to connection-close framing. The wire value
        # has already been copied into Dexpace::Headers, so only the INTERPRETATION becomes -1.
        def parse_length!(native)
          raw = native.to_hash["content-length"]
          return raw.first.to_i if raw&.size == 1 && LENGTH.match?(raw.first)

          native.delete("content-length")
          -1
        end

        # TRANSPORT-27: MediaType.parse RAISES on a malformed value rather than returning nil,
        # so this rescue is what produces "downgraded to no media type". The malformed value
        # still reaches the caller verbatim in Dexpace::Headers.
        def parse_media_type(native)
          raw = native.to_hash["content-type"]&.first
          return nil if raw.nil?

          ::Dexpace::MediaType.parse(raw)
        rescue ::Dexpace::InvalidArgumentError
          nil
        end

        # TRANSPORT-14: filtered BEFORE the values reach Headers::Builder, because it re-validates
        # and would raise on exactly the bytes this filter exists to drop; obs-text is an admitted
        # inbound byte and is kept. Each drop is logged at VERBOSE by name -- never the value.
        def filter_headers(native, logger)
          builder = ::Dexpace::Headers.inbound_builder
          native.to_hash.each do |name, values|
            next log_drop(logger, name) unless ::Dexpace::HeaderSyntax.valid_name?(name)

            values.each do |value|
              next log_drop(logger, name) unless ::Dexpace::HeaderSyntax.valid_inbound_value?(value)

              builder.add(name, value)
            end
          end
          builder.build
        end

        def log_drop(logger, name)
          event = ::Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED
          ::Dexpace::Instrumentation.contain(logger, event: event) do
            logger.event(::Dexpace::Instrumentation::Severity::VERBOSE)
              .event(event)
              .field("header", name.b)
              .field("reason", "malformed inbound header (TRANSPORT-14)")
              .emit
          end
        end
      end

      private_constant :ResponseMapper
    end
  end
end
