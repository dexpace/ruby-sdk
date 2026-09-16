# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# The request and response every phase-4b suite folds over, built once here rather than in seven
# files. Dexpace::Response is Data.define(:request, :protocol, :status, :reason, :headers, :body)
# and HTTP-4 requires all but reason and body, so a response is built through Response.builder --
# which defaults the headers to Headers::EMPTY_INBOUND -- on phase 3b's precedent; a bare
# `Response.build(status:)` is not a signature that exists.
module RecoveryFixtures
  def build_request(method: Dexpace::Method::GET, headers: Dexpace::Headers::EMPTY, body: nil)
    Dexpace::Request.build(
      method: method,
      url: "https://example.test/api",
      headers: headers,
      body: body,
    )
  end

  def build_response(code = 200, body: nil, request: build_request)
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = code
    builder.body = body
    builder.build
  end

  # ResponseBody rather than BufferBody: BufferBody wraps a Dexpace::IO::Buffer and rejects a
  # String, and a single-use closable body is what the error path actually holds.
  def response_body(content)
    Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content.b))
  end

  def headers_with(name, *values)
    values.reduce(Dexpace::Headers.builder) { |builder, value| builder.add(name, value) }.build
  end
end
