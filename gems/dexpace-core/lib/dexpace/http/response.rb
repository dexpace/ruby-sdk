# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "headers"
require_relative "protocol"
require_relative "request"
require_relative "status"

module Dexpace
  # An HTTP response: the originating request, the negotiated protocol, the status, an optional
  # reason phrase, headers and an optional body (HTTP-6).
  #
  # `body` is opaque in phase 1, as on Request. #close and the body lifecycle (HTTP-41, HTTP-43)
  # are phase 3's and are absent here rather than stubbed -- a stub would be a method whose
  # contract nothing implements.
  class Response < Data.define(:request, :protocol, :status, :reason, :headers, :body)
    include Model

    private_class_method :new

    # The validating factory every construction path goes through.
    def self.build(request:, protocol:, status:, headers:, reason: nil, body: nil)
      new(
        request: request, protocol: protocol, status: status, reason: reason, headers: headers,
        body: body,
      )
    end

    # A builder with nothing set.
    def self.builder
      Builder.new
    end

    # The required members are checked in the order HTTP-4 lists them, so a missing one fails
    # with `status is required` and names the field whether it was reached through `.build`,
    # through #with or through the builder. Protocol and status are coerced through their own
    # factories rather than trusted, as Request does with its method and URL; both factories are
    # idempotent on their own type so a builder pays nothing for it.
    #
    # The reason phrase is the one caller-supplied String this model carries, so it is copied and
    # frozen here (XCUT-15): stored as given, a later mutation of the caller's String would change
    # the model in place, and the model would not be Ractor-shareable either.
    def initialize(request:, protocol:, status:, reason:, headers:, body:)
      unless Model.required!("request", request).is_a?(Request)
        raise InvalidArgumentError, "request must be a Dexpace::Request"
      end

      negotiated = Protocol.parse(Model.required!("protocol", protocol))
      code = Status.of(Model.required!("status", status))
      unless Model.required!("headers", headers).is_a?(Headers)
        raise InvalidArgumentError, "headers must be a Dexpace::Headers"
      end
      unless reason.nil? || reason.is_a?(String)
        raise InvalidArgumentError, "reason must be a String"
      end

      super(request: request, protocol: negotiated, status: code,
            reason: reason.nil? ? nil : Model.frozen_string(reason), headers: headers, body: body)
    end

    # HTTP-3: a builder pre-filled from this instance.
    def new_builder
      Builder.new(
        request: request, protocol: protocol, status: status, reason: reason, headers: headers,
        body: body,
      )
    end

    # HTTP-11's "a response MUST expose these derived from its status": six delegations, not a
    # second copy of the ranges.
    def informational? = status.informational?
    # 200-299, delegated (HTTP-11).
    def success? = status.success?
    # 300-399, delegated (HTTP-11).
    def redirect? = status.redirect?
    # 400-499, delegated (HTTP-11).
    def client_error? = status.client_error?
    # 500-599, delegated (HTTP-11).
    def server_error? = status.server_error?
    # 400-599, delegated (HTTP-11).
    def error? = status.error?
  end
end
