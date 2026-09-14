# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"

# HTTP-14, HTTP-15, HTTP-17, HTTP-18, HTTP-19, HTTP-20, SEAM-29.
class DexpaceHeadersBuilderTest < DexpaceTestCase
  test "add appends and set replaces the whole list" do
    builder = Dexpace::Headers.builder.add("Accept", "a").add("Accept", "b")

    assert_equal(%w[a b], builder.build["Accept"])
    assert_equal(["c"], builder.set("Accept", "c").build["Accept"])
  end

  test "the first casing added is the one emitted, whatever casing later adds use" do
    headers = Dexpace::Headers.builder.add("Accept", "a").add("ACCEPT", "b").build

    assert_equal(["Accept"], headers.names)
    assert_equal(%w[a b], headers["accept"])
  end

  test "setting a value to nil removes the header entirely" do
    headers = Dexpace::Headers.builder.add("Accept", "a").set("Accept", nil).build

    refute_includes(headers, "Accept")
    assert_empty(headers.names)
  end

  test "remove drops every value of a name and forgets its casing" do
    builder = Dexpace::Headers.builder.add("Accept", "a").add("accept", "b").add("X-A", "1")

    assert_equal(["X-A"], builder.remove("ACCEPT").build.names)
    assert_equal(["X-A"], builder.remove("Absent").build.names)
  end

  test "add and set accept a HeaderName as well as a String" do
    name = Dexpace::HeaderName.of("Accept")
    headers = Dexpace::Headers.builder.add(name, "a").set(name, "b").build

    assert_equal(["b"], headers[name])
  end

  test "an outbound builder refuses obs-text and an inbound builder accepts it" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Headers.builder.add("Content-Disposition", "v\xC3\xA5lue")
    end
    inbound = Dexpace::Headers.inbound_builder.add("Content-Disposition", "v\xC3\xA5lue").build

    assert_equal(["v\xC3\xA5lue"], inbound["Content-Disposition"])
  end

  test "both directions refuse CRLF in a value" do
    [Dexpace::Headers.builder, Dexpace::Headers.inbound_builder].each do |builder|
      assert_raises(Dexpace::InvalidArgumentError) { builder.add("X-Trace", "a\r\nb") }
    end
  end

  test "a nil value on add names the missing field" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Headers.builder.add("Accept", nil)
    end

    assert_equal("header value is required", error.message)
  end

  # testing/62f8f4ec: a rejected entry leaves no partial state behind. The casing table is the
  # half that is easy to get wrong -- recording the name before validating the value leaves an
  # orphan entry that #names would report for a header the model does not carry.
  test "a rejected value leaves the builder usable and records no orphan name" do
    builder = Dexpace::Headers.builder.add("Accept", "*/*")

    assert_raises(Dexpace::InvalidArgumentError) { builder.add("X-Trace", "a\r\nb") }

    built = builder.build

    assert_equal(["Accept"], built.names)
    refute_includes(built, "X-Trace")
    assert_equal(["*/*"], builder.add("Accept", "text/plain").build["Accept"].first(1))
  end

  test "a rejected name leaves no partial state either" do
    builder = Dexpace::Headers.builder.add("Accept", "*/*")

    assert_raises(Dexpace::InvalidArgumentError) { builder.add("a\r\nb", "x") }
    assert_equal(["Accept"], builder.build.names)
  end

  test "the error message names the header and never echoes the value" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Headers.builder.add("Authorization", "Bearer secret\r\ntoken")
    end

    assert_includes(error.message, "Authorization")
    refute_includes(error.message, "secret")
  end

  test "building twice yields two independent models" do
    builder = Dexpace::Headers.builder.add("Accept", "a")
    first = builder.build
    builder.add("Accept", "b")

    assert_equal(["a"], first["Accept"])
    assert_equal(%w[a b], builder.build["Accept"])
  end

  test "implements the shared builder contract" do
    assert_kind_of(Dexpace::Builder, Dexpace::Headers.builder)
    assert_equal(:outbound, Dexpace::Headers.builder.direction)
    assert_equal(:inbound, Dexpace::Headers.inbound_builder.direction)
  end
end
