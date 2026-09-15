# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"

# HTTP-4, HTTP-7, HTTP-8, HTTP-18, HTTP-47, SEAM-29.
class DexpaceRequestBuilderTest < DexpaceTestCase
  def builder(url: "https://example.test/")
    Dexpace::Request.builder.tap { |b| b.url = url }
  end

  test "requires a URL and names the missing field" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Request.builder.build }

    assert_equal("url is required", error.message)
  end

  test "defaults the method to GET when there is neither a method nor a body" do
    assert_equal(Dexpace::Method::GET, builder.build.method)
  end

  test "a body with no method reports the missing method, not the no-body-on-GET rule" do
    with_body = builder
    with_body.body = "payload"
    error = assert_raises(Dexpace::InvalidArgumentError) { with_body.build }

    assert_equal("method is required", error.message)
  end

  test "rejects a body on every method whose classification forbids one" do
    %w[GET HEAD TRACE CONNECT].each do |token|
      forbidden = builder
      forbidden.method = token
      forbidden.body = "payload"
      error = assert_raises(Dexpace::InvalidArgumentError, token) { forbidden.build }

      assert_includes(error.message, token)
    end
  end

  test "clearing the body makes a GET buildable again" do
    cleared = builder
    cleared.method = "GET"
    cleared.body = "payload"
    cleared.body = nil

    assert_equal(Dexpace::Method::GET, cleared.build.method)
  end

  test "accepts a body on POST and a method given as a Method, a Symbol or lower-case text" do
    posted = builder
    posted.method = "post"
    posted.body = "payload"

    assert_equal("payload", posted.build.body)
    assert_equal(Dexpace::Method::POST, posted.build.method)
    posted.method = :put

    assert_equal(Dexpace::Method::PUT, posted.build.method)
    posted.method = Dexpace::Method::PATCH

    assert_equal(Dexpace::Method::PATCH, posted.build.method)
  end

  test "rejects a malformed URL with the offending input in the message" do
    error = assert_raises(Dexpace::InvalidArgumentError) { builder(url: "::bad").build }

    assert_includes(error.message, "::bad")
  end

  test "header derives a new Headers into the builder, so build sees every header set this way" do
    built = builder.header("Accept", "*/*").header("X-Trace", "1").build

    assert_equal(%w[Accept X-Trace], built.headers.names)
    assert_equal(["*/*"], built.headers["accept"])
  end

  test "headers= replaces the collection and header appends to it afterwards" do
    with_headers = builder
    with_headers.headers = Dexpace::Headers.builder.add("Accept", "*/*").build
    built = with_headers.header("X-Trace", "1").build

    assert_equal(%w[Accept X-Trace], built.headers.names)
    assert_raises(Dexpace::InvalidArgumentError) { with_headers.headers = {} }
  end

  # HTTP-18: an inbound-validated collection is refused where it is set, not only at build,
  # because #header derives its builder from @headers -- an inbound one would hand back a lenient
  # builder that accepts a byte Request.builder.header alone rejects. The rejection leaves no
  # partial state: the next #header still validates by the outbound grammar.
  test "headers= and the pre-filled constructor refuse inbound-validated headers" do
    inbound = Dexpace::Headers.inbound_builder.add("X-Trace", "v\xC3\xA5lue").build
    with_headers = builder
    error = assert_raises(Dexpace::InvalidArgumentError) { with_headers.headers = inbound }

    assert_includes(error.message, "outbound")
    assert_raises(Dexpace::InvalidArgumentError) { with_headers.header("X-Other", "\xE9") }
    assert_same(Dexpace::Headers::EMPTY, with_headers.build.headers)
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Request::Builder.new(headers: inbound) }
  end

  test "an empty request carries the outbound empty headers" do
    assert_same(Dexpace::Headers::EMPTY, builder.build.headers)
  end

  test "a rejected header leaves the builder usable with no partial state" do
    partial = builder.header("Accept", "*/*")

    assert_raises(Dexpace::InvalidArgumentError) { partial.header("X-Trace", "a\r\nb") }
    assert_equal(["Accept"], partial.build.headers.names)
  end

  test "implements the shared builder contract" do
    assert_kind_of(Dexpace::Builder, Dexpace::Request.builder)
  end
end
