# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"

module Dexpace
  # An HTTP status code, total over the protocol's range (HTTP-10 - HTTP-12).
  #
  # ONE member, and that is HTTP-12 rather than minimalism: two Status values must be equal iff
  # their codes are equal, with the name taking no part. A Data.define(:code, :name) would generate
  # equality over both members and violate that silently -- a vendor 520 with no name would not
  # equal a 520 someone had named. The canonical name is a lookup, which is also what HTTP-10's
  # "a separate lookup MUST let callers distinguish recognized codes" asks for.
  class Status < Data.define(:code)
    include Model

    private_class_method :new

    # The recognised codes and their reason phrases; every other code in range is a vendor code.
    CANONICAL_NAMES = {
      100 => "Continue", 101 => "Switching Protocols",
      200 => "OK", 201 => "Created", 202 => "Accepted", 204 => "No Content",
      206 => "Partial Content",
      301 => "Moved Permanently", 302 => "Found", 303 => "See Other", 304 => "Not Modified",
      307 => "Temporary Redirect", 308 => "Permanent Redirect",
      400 => "Bad Request", 401 => "Unauthorized", 403 => "Forbidden", 404 => "Not Found",
      405 => "Method Not Allowed", 406 => "Not Acceptable", 408 => "Request Timeout",
      409 => "Conflict", 410 => "Gone", 412 => "Precondition Failed",
      413 => "Content Too Large", 415 => "Unsupported Media Type",
      422 => "Unprocessable Content", 425 => "Too Early", 428 => "Precondition Required",
      429 => "Too Many Requests", 431 => "Request Header Fields Too Large",
      500 => "Internal Server Error", 501 => "Not Implemented", 502 => "Bad Gateway",
      503 => "Service Unavailable", 504 => "Gateway Timeout",
      505 => "HTTP Version Not Supported", 507 => "Insufficient Storage",
      511 => "Network Authentication Required",
    }.freeze

    # The validating factory every construction path goes through.
    def self.build(code:)
      new(code: code)
    end

    # Idempotent on a Status, like Method.of and HeaderName.of: #with and Response#initialize both
    # pass whatever they were given straight back in, and a factory that only accepts raw input
    # makes every caller write the type check instead.
    def self.of(code)
      return code if code.is_a?(Status)

      build(code: code)
    end

    # HTTP-10's separate lookup: the canonical name, or nil for a code this table does not know.
    def self.canonical_name(code)
      CANONICAL_NAMES[code]
    end

    # HTTP-10 says construction is total over "any code"; the 100-599 guard is the port's reading
    # and not a narrowing of it. A vendor code such as nginx's 499 or Cloudflare's 520-526 and 530
    # is inside the range and constructs cleanly with no name, which is the requirement's own
    # rationale; an Integer outside the protocol's range is a caller mistake, not a vendor code.
    def initialize(code:)
      Model.required!("code", code)
      unless code.is_a?(Integer) && code.between?(100, 599)
        raise InvalidArgumentError, "code must be an integer status code between 100 and 599"
      end

      super
    end

    # The reason phrase for a recognised code; nil for a vendor code (HTTP-10).
    def canonical_name
      CANONICAL_NAMES[code]
    end

    # 100-199 (HTTP-11).
    def informational? = code.between?(100, 199)
    # 200-299 (HTTP-11).
    def success? = code.between?(200, 299)
    # 300-399 (HTTP-11).
    def redirect? = code.between?(300, 399)
    # 400-499 (HTTP-11).
    def client_error? = code.between?(400, 499)
    # 500-599 (HTTP-11).
    def server_error? = code.between?(500, 599)
    # 400-599: either error class (HTTP-11).
    def error? = code.between?(400, 599)

    # 200 OK. Every named constant equals `Status.of` of its code; they exist so a caller can
    # compare against a recognised code without writing the number.
    OK = of(200)
    # 201 Created.
    CREATED = of(201)
    # 204 No Content.
    NO_CONTENT = of(204)
    # 304 Not Modified.
    NOT_MODIFIED = of(304)
    # 400 Bad Request.
    BAD_REQUEST = of(400)
    # 401 Unauthorized.
    UNAUTHORIZED = of(401)
    # 403 Forbidden.
    FORBIDDEN = of(403)
    # 404 Not Found.
    NOT_FOUND = of(404)
    # 408 Request Timeout.
    REQUEST_TIMEOUT = of(408)
    # 429 Too Many Requests.
    TOO_MANY_REQUESTS = of(429)
    # 500 Internal Server Error.
    INTERNAL_SERVER_ERROR = of(500)
    # 501 Not Implemented.
    NOT_IMPLEMENTED = of(501)
    # 502 Bad Gateway.
    BAD_GATEWAY = of(502)
    # 503 Service Unavailable.
    SERVICE_UNAVAILABLE = of(503)
    # 504 Gateway Timeout.
    GATEWAY_TIMEOUT = of(504)
  end
end
