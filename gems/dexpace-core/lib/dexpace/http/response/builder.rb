# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../builder"
require_relative "../../error/invalid_argument_error"
require_relative "../../model"
require_relative "../headers"
require_relative "../request"

module Dexpace
  class Response
    # The mutable assembler for a Response (HTTP-4, HTTP-6).
    #
    # A writer per member and a #build that defaults `headers` to Headers::EMPTY_INBOUND -- a
    # response's headers are inbound, and defaulting to the outbound empty would make
    # `response.headers.new_builder` a strict builder that refuses obs-text (HTTP-19). The
    # required-field checks live in the model, so #build is a plain delegation.
    class Builder
      include Dexpace::Builder

      # HTTP-3: a builder pre-filled from a model; every member is a frozen value.
      def initialize(request: nil, protocol: nil, status: nil, reason: nil, headers: nil, body: nil)
        @request = request
        @protocol = protocol
        @status = status
        @reason = reason
        @headers = headers
        @body = body
      end

      # The negotiated protocol, as an identifier or a Protocol.
      attr_writer :protocol
      # The status, as a code or a Status.
      attr_writer :status
      # The reason phrase; nil clears it. The model copies and freezes it at build, so the
      # builder may hold the caller's live String.
      attr_writer :reason
      # The body, opaque in phase 1; nil clears it.
      attr_writer :body

      # The originating request; checked here so the mistake is reported where it was made.
      def request=(request)
        unless request.is_a?(Request)
          raise InvalidArgumentError, "request must be a Dexpace::Request"
        end

        @request = request
      end

      # The response headers, a Headers built by an inbound builder.
      def headers=(headers)
        unless headers.is_a?(Headers)
          raise InvalidArgumentError, "headers must be a Dexpace::Headers"
        end

        @headers = headers
      end

      # The frozen model; the builder stays usable and later mutation does not reach it. The
      # three required members are checked here first, in HTTP-4's order, and again by the
      # model, which is the check that cannot be bypassed.
      def build
        Response.build(
          request: Model.required!("request", @request),
          protocol: Model.required!("protocol", @protocol),
          status: Model.required!("status", @status),
          reason: @reason, headers: @headers || Headers::EMPTY_INBOUND, body: @body,
        )
      end
    end
  end
end
