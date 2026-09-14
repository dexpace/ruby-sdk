# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../builder"
require_relative "../../model"
require_relative "../headers"
require_relative "../method"
require_relative "../url"

module Dexpace
  class Request
    # The mutable assembler for a Request (HTTP-4, HTTP-7, HTTP-8, HTTP-47).
    #
    # It carries exactly the rule that is about a field nobody set -- HTTP-8's method defaulting
    # -- because a model that already has the field cannot express it; everything else is
    # re-checked by Request.build, which is the check that cannot be bypassed.
    class Builder
      include Dexpace::Builder

      # HTTP-3: a builder pre-filled from a model. The headers are a frozen Headers, so holding
      # the reference aliases nothing a later #header can reach into.
      def initialize(method: nil, url: nil, headers: nil, body: nil)
        @method = method
        @url = url
        @headers = headers
        @body = body
      end

      # The method token, as a String, Symbol or Method; nil to default it at build (HTTP-8).
      attr_writer :method
      # The target URL, as a String or a URI (HTTP-47).
      attr_writer :url
      # The body, opaque in phase 1; nil clears it.
      attr_writer :body

      # A Headers built elsewhere -- phase 2 assigns one directly -- replacing what #header set.
      def headers=(headers)
        unless headers.is_a?(Headers)
          raise InvalidArgumentError, "headers must be a Dexpace::Headers"
        end

        @headers = headers
      end

      # Appends one header. This derives a new Headers into @headers rather than keeping a second,
      # unread builder beside it: #headers= stores a Headers and #build reads @headers, so an
      # accumulator the build never consulted would silently drop every header set this way.
      def header(name, value)
        @headers = (@headers || Headers::EMPTY).new_builder.add(name, value).build
        self
      end

      # HTTP-4, then HTTP-8, then HTTP-7 -- in that order, because the missing-method error must
      # be reported before the no-body rule can name the wrong mistake.
      def build
        url = URL.parse!(Model.required!("url", @url)) # HTTP-4 and HTTP-47, in one call
        # HTTP-8: GET only when there is nothing to send. A body with no method reports the
        # MISSING METHOD rather than defaulting to GET and then tripping HTTP-7's no-body rule,
        # which would name the wrong mistake.
        token = @method
        token = @body.nil? ? Method::GET : Model.required!("method", token) if token.nil?
        method = Method.of(token)
        if method.body_forbidden? && !@body.nil?
          raise InvalidArgumentError, "a #{method} request must not carry a body (HTTP-7)"
        end

        Request.build(method: method, url: url, headers: @headers || Headers::EMPTY, body: @body)
      end
    end
  end
end
