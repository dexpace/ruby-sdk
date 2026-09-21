# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/adapter_fixtures"
require "dexpace/transport/net_http"
require "dexpace/conformance"
require "dexpace/serde/json"

# The generator slice, end to end over the first real socket in the repository: SEAM-26 (the
# operation descriptor), SEAM-27 (the typed response), SERDE-28 (the status-aware handler),
# RECOV-15 (the error carrying a buffered body), PIPE-39 (the standard pipeline over a builder),
# HTTP-52/BODY-30 (Tristate omission; the snapshot error body). None is 8a's row: this is the
# composition test, and it adds no implementation. The codec half names phase 7a's
# Dexpace::Serde::JSON::Codec: it was guarded with a skip while 8a was built one base apart from
# 7a, and it runs against the real codec since the stack was reconciled onto the tree that holds
# it (2026-09-21); the two socket-only halves never needed the guard.
class DexpaceTransportNetHttpGeneratorSliceTest < DexpaceTestCase
  include AdapterFixtures

  NetHTTP = Dexpace::Transport::NetHTTP
  Scripts = Dexpace::Conformance::Scripts

  # A witness is a named object answering .dexpace_load (7a's Serde.witness! contract).
  class Pet
    attr_reader :name

    def self.dexpace_load(parsed, _context)
      new(parsed["name"])
    end

    def initialize(name)
      @name = name
    end
  end

  # The smallest object answering the step protocol at Stages::AUTH that stamps a bearer: 6c's
  # Auth::Step refuses a plaintext URL (AUTH-28) and the fixture speaks plaintext only (P8-9), so
  # the assertion here is about the pipeline seeding a step at that stage and the stamped request
  # reaching the wire, not about 6c's constructor.
  class BearerStep
    def stage
      Dexpace::Pipeline::Stages::AUTH
    end

    def call(request, cursor)
      headers = request.headers.new_builder.set("Authorization", "Bearer t0ken").build
      cursor.fork.call(request.with(headers: headers))
    end
  end

  def operation
    Dexpace::Operation.build(method: "GET", template: "/pets/{id}",
                             projections: { id: [:path, "id"] },)
  end

  def base_url(server)
    "http://127.0.0.1:#{server.port}"
  end

  # SEAM-26's path expansion: a projected path value containing "/" is ONE segment on the wire.
  test "SEAM-26: a path parameter containing a slash reaches the server as one escaped segment" do
    server = wire(Scripts.fixed("{}"))
    request = operation.build_request(base_url: base_url(server), inputs: { id: "a/b" })

    settle(NetHTTP.build, request).close

    line = server.requests.first.request_line

    assert_includes(line, "/pets/a%2Fb")
    refute_includes(line, "/pets/a/b")
  end

  # PIPE-39 with an AUTH-stage step, seeded the documented way: a Pipeline::Builder handed to
  # Pipeline.standard as its one positional (6b's Task 13a; PIPE-24's validate-then-commit).
  test "PIPE-39: an AUTH-stage step seeded through a builder stamps the wire request" do
    server = wire(Scripts.fixed("{}"))
    adapter = NetHTTP.build
    builder = Dexpace::Pipeline.builder(transport: adapter)
    builder.append(BearerStep.new)
    pipeline = Dexpace::Pipeline.standard(builder)
    request = operation.build_request(base_url: base_url(server), inputs: { id: "7" })

    pipeline.call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none).close

    assert_equal("Bearer t0ken", server.requests.first.header("authorization"))
    assert_equal("GET /pets/7 HTTP/1.1", server.requests.first.request_line)
  end

  # SEAM-27, SERDE-28, RECOV-15, BODY-30 and HTTP-52 in one test: a 200 decodes to the
  # witness's type; a 404 raises an error whose buffered body is still readable after the socket
  # is gone; an ABSENT field is omitted from a PATCH body and a NULL one is not.
  test "SEAM-27/SERDE-28/RECOV-15/BODY-30/HTTP-52: the codec half of the slice" do
    serde = Dexpace::Serde
    codec = serde::JSON::Codec.default
    handler = serde::StatusAwareHandler.build(serde: codec, witness: Pet)

    ok = wire(Scripts.fixed('{"name":"Rex"}'))
    request = operation.build_request(base_url: base_url(ok), inputs: { id: "7" })
    response = Dexpace::Pipeline.standard(NetHTTP.build)
      .call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)

    assert_equal("Rex", Dexpace::TypedResponse.new(response: response, handler: handler).value.name)

    missing = wire(Scripts.vendor_status(404, '{"error":"no such pet"}'))
    request = operation.build_request(base_url: base_url(missing), inputs: { id: "7" })
    response = Dexpace::Pipeline.standard(NetHTTP.build)
      .call(request, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none)
    error = assert_raises(Dexpace::ProtocolError) do
      Dexpace::TypedResponse.new(response: response, handler: handler).value
    end

    assert_equal(404, error.status.code)
    refute_nil(error.response.headers)
    assert_match(/no such pet/, error.response.body_string)
    assert_match(/no such pet/, error.response.body_string) # twice, after the socket is gone

    patch = Dexpace::Operation.build(method: "PATCH", template: "/pets/{id}",
                                     projections: { id: [:path, "id"], body: [:body, "body"] },)
    echo = wire(Scripts.fixed("{}"))
    encoded = codec.dump_bytes("name" => serde::Tristate::ABSENT, "tag" => serde::Tristate::NULL)
    body = Dexpace::Body.bytes(encoded, media_type: Dexpace::MediaType.parse("application/json"))
    request = patch.build_request(base_url: base_url(echo), inputs: { id: "7", body: body })

    settle(NetHTTP.build, request).close

    refute_includes(echo.requests.first.body, "name")
    assert_includes(echo.requests.first.body, "tag")
  end
end
