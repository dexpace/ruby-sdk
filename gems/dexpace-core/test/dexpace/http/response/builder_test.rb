# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"

# HTTP-4, HTTP-6, HTTP-19, SEAM-29.
class DexpaceResponseBuilderTest < DexpaceTestCase
  def request
    builder = Dexpace::Request.builder
    builder.url = "https://example.test/"
    builder.build
  end

  test "sets every member and builds the model" do
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_2
    builder.status = Dexpace::Status::CREATED
    builder.reason = "Created"
    builder.headers = Dexpace::Headers.inbound_builder.add("Location", "/x").build
    builder.body = "payload"
    built = builder.build

    assert_equal(Dexpace::Protocol::HTTP_2, built.protocol)
    assert_equal(Dexpace::Status::CREATED, built.status)
    assert_equal("Created", built.reason)
    assert_equal(["/x"], built.headers["location"])
    assert_equal("payload", built.body)
  end

  test "checks the request and the headers as they are set" do
    builder = Dexpace::Response.builder

    assert_raises(Dexpace::InvalidArgumentError) { builder.request = "GET /" }
    assert_raises(Dexpace::InvalidArgumentError) { builder.headers = { "a" => "b" } }
  end

  test "defaults the headers to the inbound empty" do
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = "http/1.1"
    builder.status = 204

    assert_same(Dexpace::Headers::EMPTY_INBOUND, builder.build.headers)
  end

  test "building twice yields two independent models" do
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = "http/1.1"
    builder.status = 200
    first = builder.build
    builder.status = 500

    assert_equal(Dexpace::Status::OK, first.status)
    assert_equal(Dexpace::Status::INTERNAL_SERVER_ERROR, builder.build.status)
  end

  test "implements the shared builder contract" do
    assert_kind_of(Dexpace::Builder, Dexpace::Response.builder)
  end
end
