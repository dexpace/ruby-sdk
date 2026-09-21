# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module NetHTTP
      # R2's eight steps, in order, as one function returning a Net::HTTPGenericRequest. The only
      # place in this gem that touches Dexpace::HeaderSyntax, the only place that reads
      # MANAGED_HEADERS, and the only place that constructs a native request. TRANSPORT-17's
      # adapter-discipline half ("MUST NOT itself trigger a second write") is a property of this
      # file's shape: `body_stream=` is assigned exactly once, on the one path through `.build`,
      # and nothing here loops. A private_constant of NetHTTP.
      module RequestMapper
        extend self

        # The three headers Net::HTTPGenericRequest#initialize stamps on every request and this
        # adapter deletes (P8-2): the wire carries the caller's header set and nothing else.
        AUTO_STAMPS = %w[Accept Accept-Encoding User-Agent].freeze
        private_constant :AUTO_STAMPS

        # @param request [Dexpace::Request] the request to send, or anything duck-typed like one
        # @param logger [Dexpace::Instrumentation::Logger] where each managed-header drop is logged
        #   at VERBOSE (TRANSPORT-11)
        # @return [Net::HTTPGenericRequest]
        # @raise [Dexpace::InvalidArgumentError] when an outbound header name or value fails the
        #   wire-boundary re-validation (HTTP-17, HTTP-18)
        def build(request, logger:)
          revalidate!(request)

          body_permitted = !request.method.body_forbidden?
          native = native_request(request, body_permitted)
          copy_headers(request, native, logger)
          suppress_decode_content(native)
          set_content_type(request, native, body_permitted)
          attach_body(request, native, body_permitted)
          native
        end

        private

        # An empty header set, the three auto-stamps deleted as soon as they are stamped.
        def native_request(request, body_permitted)
          native = ::Net::HTTPGenericRequest.new(request.method.token, body_permitted,
                                                 request.method.token != "HEAD",
                                                 request.url.request_uri, {})
          AUTO_STAMPS.each { |name| native.delete(name) }
          native
        end

        # The wire-boundary re-validation phase 1 postponed to the adapters (HTTP-17, HTTP-18,
        # XCUT-18): every outbound name and value is checked again immediately before dispatch,
        # BEFORE anything is copied, because HTTP-2's constructor privacy is bypassable and a
        # duck-typed impostor can reach this code with no Dexpace validation ever having run.
        # Measured: Net::HTTP#[]= rejects a CR/LF VALUE but writes a CR/LF NAME straight to the
        # wire, so the name half is the half with no native backstop.
        def revalidate!(request)
          request.headers.each_entry do |name, value|
            ::Dexpace::HeaderSyntax.validate_name!(name)
            ::Dexpace::HeaderSyntax.validate_outbound_value!(value, name: name)
          end
        end

        # TRANSPORT-11: the caller's headers minus MANAGED_HEADERS, each drop logged once. `Host`
        # is the one that needs saying: Net::HTTP fills it from the URL only when the slot is
        # empty, so a caller's value that reached the native request would be honoured verbatim.
        def copy_headers(request, native, logger)
          request.headers.each_entry do |name, value|
            if MANAGED_HEADERS.include?(::Dexpace::HeaderName.of(name).folded)
              log_drop(logger, name)
            else
              native.add_field(name, value)
            end
          end
        end

        # P8-3: the switch is `#[]=`, never `#add_field`, because only `#[]=` flips
        # @decode_content off as a side effect. Re-assigning the caller's own value preserves it
        # while still tripping the flip; assigning then deleting leaves the flag off and the
        # header absent when the caller set none.
        def suppress_decode_content(native)
          caller_value = native["Accept-Encoding"]
          if caller_value
            native["Accept-Encoding"] = caller_value
          else
            native["Accept-Encoding"] = "identity"
            native.delete("Accept-Encoding")
          end
        end

        # TRANSPORT-10 and P8-4 together: the caller's explicit header wins (matched
        # case-insensitively, because Net::HTTPHeader#key? folds); failing that the body's own
        # media type; failing that DEFAULT_CONTENT_TYPE -- and only ever on a body-permitted
        # method, body or not, because Net::HTTP gives every body-permitted request a body and its
        # own fallback would stamp a form type the wire should never carry.
        def set_content_type(request, native, body_permitted)
          return if !body_permitted || native.key?("Content-Type")

          media = request.body&.media_type
          native["Content-Type"] = media ? media.render : DEFAULT_CONTENT_TYPE
        end

        # Framing is derived from the body and never copied: Content-Length from a known length,
        # `Transfer-Encoding: chunked` from an unknown one, neither when there is no body -- a
        # body-less body-permitted request is left to Net::HTTP, which substitutes a zero-length
        # body with `Content-Length: 0` itself (TRANSPORT-26). The body goes out as a stream
        # through 3a's `.over`, which owns nothing and pulls from `#each` on demand.
        def attach_body(request, native, body_permitted)
          body = request.body
          return unless body_permitted && body

          length = body.content_length
          if length >= 0
            native["Content-Length"] = length.to_s
          else
            native["Transfer-Encoding"] = "chunked"
          end
          native.body_stream = ::Dexpace::IO::BufferedSource.over(body)
        end

        # The shared transport contract's one event and field pair, so one conformance assertion
        # reads a drop record from either adapter.
        def log_drop(logger, name)
          event = ::Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED
          ::Dexpace::Instrumentation.contain(logger, event: event) do
            logger.event(::Dexpace::Instrumentation::Severity::VERBOSE)
              .event(event)
              .field("header", name)
              .field("reason", "transport managed header (TRANSPORT-11)")
              .emit
          end
        end
      end

      private_constant :RequestMapper
    end
  end
end
