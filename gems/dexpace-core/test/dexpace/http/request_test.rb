# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-1, HTTP-2, HTTP-3, HTTP-4, HTTP-5, HTTP-6, HTTP-7, HTTP-46, HTTP-47, XCUT-15.
class DexpaceRequestTest < DexpaceTestCase
  def request(url: "https://example.test/a")
    builder = Dexpace::Request.builder
    builder.url = url
    builder.header("Accept", "*/*")
    builder.build
  end

  test "carries exactly method, url, headers and body" do
    built = request

    assert_equal(%i[method url headers body], built.to_h.keys)
    assert_equal(Dexpace::Method::GET, built.method)
    assert_kind_of(::URI::Generic, built.url)
    assert_equal(["*/*"], built.headers["Accept"])
    assert_nil(built.body)
  end

  test "two requests to the same textual URL are equal, with no name resolution" do
    assert_equal(request, request)
    assert(request.eql?(request))
  end

  test "two textually different URLs are not equal even when they name the same host" do
    refute_equal(request(url: "https://example.test/a"), request(url: "https://example.test/a/"))
  end

  test "equality compares method, headers and body by value" do
    other = request.new_builder
    other.header("Accept", "text/plain")

    refute_equal(request, other.build)
    posted = request.new_builder
    posted.method = "POST"
    posted.body = "payload"

    refute_equal(request, posted.build)
    assert_equal(posted.build, posted.build)
    refute_equal(request, "not a request")
  end

  test "hash agrees with equality" do
    assert_equal(request.hash, request.hash)
    refute_equal(request.hash, request(url: "https://example.test/b").hash)
  end

  # Deviation P1-9 expected the URI member to keep a Request out of Ractor-shareable, because
  # URI::Generic#freeze is shallow and the only remedy the design saw, Ractor.make_shareable(uri),
  # would deep-freeze URI::RFC3986_PARSER in place. As built, URL.parse! freezes the component
  # Strings it owns (which XCUT-15 needs anyway, since a reader hands them out), and the parser is
  # already frozen by the uri gem on 3.2.11 and 4.0.6 -- so the model is shareable with no global
  # touched, given a nil or frozen body (the body is opaque here and carried as given). Ractor is
  # load-bearing nowhere in this port; this is the free side effect design §4 claims, asserted so
  # a later change to URL.parse! cannot lose it silently.
  test "is frozen, and Ractor-shareable because the URL's components are frozen with it" do
    built = request

    assert_predicate(built, :frozen?)
    assert_predicate(built.url, :frozen?)
    assert(Ractor.shareable?(built.headers))
    assert(Ractor.shareable?(built))
    assert_predicate(::URI::RFC3986_PARSER, :frozen?)
  end

  test "new_builder is pre-filled and does not alias the original's headers" do
    original = request
    derived = original.new_builder
    derived.header("X-Trace", "1")

    refute_includes(original.headers, "X-Trace")
    assert_includes(derived.build.headers, "X-Trace")
    assert_equal(original.url, derived.build.url)
  end

  test "with re-validates HTTP-7, so a GET cannot acquire a body by derivation" do
    assert_raises(Dexpace::InvalidArgumentError) { request.with(body: "payload") }
    assert_equal(Dexpace::Method::POST, request.with(method: "POST", body: "x").method)
  end

  test "build coerces a method token and a URL string into their types" do
    built = Dexpace::Request.build(
      method: "post", url: "https://example.test/a", headers: Dexpace::Headers::EMPTY, body: nil,
    )

    assert_equal(Dexpace::Method::POST, built.method)
    assert_equal("https://example.test/a", Dexpace::URL.external_form(built.url))
  end

  test "build rejects a method token, a URL and a headers value it cannot coerce" do
    empty = Dexpace::Headers::EMPTY

    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Request.build(method: "GE T", url: "https://example.test/", headers: empty)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Request.build(method: "GET", url: "::bad", headers: empty, body: nil)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Request.build(method: "GET", url: "https://example.test/", headers: {}, body: nil)
    end
  end

  test "build names a missing member through the shared required-field helper" do
    %w[method url headers].each do |name|
      members = { method: "GET", url: "https://example.test/", headers: Dexpace::Headers::EMPTY }
      members[name.to_sym] = nil
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Request.build(**members, body: nil)
      end

      assert_equal("#{name} is required", error.message)
    end
  end

  # HTTP-2's residual gap, asserted rather than papered over (design §10.10, §11.6). `send`
  # bypassing `private` is a documented Ruby feature and cannot be closed; the mitigation is that
  # HTTP-17/HTTP-18 are re-validated at the model-to-wire boundary inside every transport (phase
  # 8a Task 16, phase 8c Task 9), which makes this a correctness-of-shape gap and not a
  # request-splitting one. A test asserting this path is blocked would be a lie that passes.
  test "send reaches the private constructor, and that hole is documented not closed" do
    url = Dexpace::URL.parse!("https://example.test/")
    forged = Dexpace::Request.send(
      :new, method: Dexpace::Method::GET, url: url, headers: Dexpace::Headers::EMPTY, body: nil,
    )

    assert_instance_of(Dexpace::Request, forged)
    assert_raises(NoMethodError) { Dexpace::Request.new(method: nil, url: nil, headers: nil) }
  end
end
