# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-3, HTTP-4, HTTP-5, HTTP-6, HTTP-11, HTTP-19. The `.build` coercion and rejection cases have
# their own nested group, BuildTest, so the file keeps one top-level suite per lib file.
class DexpaceResponseTest < DexpaceTestCase
  def response(status: Dexpace::Status::OK)
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = status
    builder.build
  end

  def request
    builder = Dexpace::Request.builder
    builder.url = "https://example.test/"
    builder.build
  end

  test "carries exactly request, protocol, status, reason, headers and body" do
    assert_equal(%i[request protocol status reason headers body], response.to_h.keys)
    assert_equal(request, response.request)
    assert_equal(Dexpace::Protocol::HTTP_1_1, response.protocol)
    assert_equal(Dexpace::Status::OK, response.status)
  end

  test "requires the request, the protocol and the status, naming the missing field" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Response.builder.build }

    assert_equal("request is required", error.message)
  end

  test "names the missing status when only that is absent" do
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    error = assert_raises(Dexpace::InvalidArgumentError) { builder.build }

    assert_equal("status is required", error.message)
  end

  test "names the missing protocol when only that is absent" do
    builder = Dexpace::Response.builder
    builder.request = request
    builder.status = 200
    error = assert_raises(Dexpace::InvalidArgumentError) { builder.build }

    assert_equal("protocol is required", error.message)
  end

  test "carries an optional reason phrase and an optional body, and empty headers by default" do
    built = response

    assert_nil(built.reason)
    assert_nil(built.body)
    assert_predicate(built.headers, :empty?)
    with_reason = built.new_builder
    with_reason.reason = "OK"
    with_reason.body = "payload"

    assert_equal("OK", with_reason.build.reason)
    assert_equal("payload", with_reason.build.body)
  end

  # HTTP-19: the default is the INBOUND empty, so deriving from a header-less response yields a
  # builder that still accepts obs-text rather than one that refuses it.
  test "defaults its headers to the inbound empty, so a derived builder stays lenient" do
    derived = response.headers.new_builder

    assert_same(Dexpace::Headers::EMPTY_INBOUND, response.headers)
    assert_equal(:inbound, response.headers.direction)
    lenient = derived.add("Content-Disposition", "v\xC3\xA5lue").build

    assert_equal(["v\xC3\xA5lue"], lenient["Content-Disposition"])
  end

  test "derives its classification from its status rather than restating the ranges" do
    assert_predicate(response, :success?)
    assert_predicate(response(status: Dexpace::Status.of(101)), :informational?)
    assert_predicate(response(status: Dexpace::Status.of(302)), :redirect?)
    assert_predicate(response(status: Dexpace::Status.of(404)), :client_error?)
    assert_predicate(response(status: Dexpace::Status.of(503)), :server_error?)
    assert_predicate(response(status: Dexpace::Status.of(404)), :error?)
    refute_predicate(response, :error?)
  end

  test "is frozen and derives without aliasing" do
    built = response
    derived = built.new_builder
    derived.status = Dexpace::Status::NOT_FOUND
    derived.headers = Dexpace::Headers.inbound_builder.add("X-A", "1").build

    assert_predicate(built, :frozen?)
    assert_equal(Dexpace::Status::OK, built.status)
    assert_predicate(built.headers, :empty?)
    assert_equal(Dexpace::Status::NOT_FOUND, derived.build.status)
    assert_equal(["1"], derived.build.headers["X-A"])
  end

  test "with re-validates, so a derived response cannot carry a status outside the range" do
    assert_raises(Dexpace::InvalidArgumentError) { response.with(status: 600) }
    assert_raises(Dexpace::InvalidArgumentError) { response.with(protocol: nil) }
    assert_equal(Dexpace::Status::NOT_FOUND, response.with(status: 404).status)
  end

  test "is Ractor-shareable, like the request it carries" do
    assert(Ractor.shareable?(response))
  end

  # HTTP-4: what `.build` coerces and what it refuses, whichever path reached it. Nested so the
  # file keeps one top-level suite per lib file.
  class BuildTest < DexpaceTestCase
    def request
      builder = Dexpace::Request.builder
      builder.url = "https://example.test/"
      builder.build
    end

    def response(status: Dexpace::Status::OK)
      builder = Dexpace::Response.builder
      builder.request = request
      builder.protocol = Dexpace::Protocol::HTTP_1_1
      builder.status = status
      builder.build
    end

    test "build coerces a protocol identifier and a status code into their types" do
      builder = Dexpace::Response.builder
      builder.request = request
      builder.protocol = "HTTP/2.0"
      builder.status = 404
      built = builder.build

      assert_equal(Dexpace::Protocol::HTTP_2, built.protocol)
      assert_equal(Dexpace::Status::NOT_FOUND, built.status)
      assert_predicate(built, :client_error?)
    end

    test "build rejects a protocol, a status, a request and headers it cannot coerce" do
      assert_raises(Dexpace::InvalidArgumentError) { response(status: 99) }
      builder = Dexpace::Response.builder
      builder.request = request
      builder.protocol = "spdy/3"
      builder.status = Dexpace::Status::OK

      assert_raises(Dexpace::InvalidArgumentError) { builder.build }
      assert_raises(Dexpace::InvalidArgumentError) { builder.request = "not a request" }
      assert_raises(Dexpace::InvalidArgumentError) { builder.headers = {} }
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Response.build(
          request: "x", protocol: "http/1.1", status: 200, headers: Dexpace::Headers::EMPTY_INBOUND,
        )
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Response.build(request: request, protocol: "http/1.1", status: 200, headers: {})
      end
    end
  end
end
