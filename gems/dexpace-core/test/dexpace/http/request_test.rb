# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require "stringio"

# HTTP-1, HTTP-2, HTTP-3, HTTP-4, HTTP-5, HTTP-6, HTTP-7, HTTP-18, HTTP-46, HTTP-47, XCUT-15,
# XCUT-18.
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

  # HTTP-46's body half, untestable in phase 1 because no body type existed. Phase 3b supplies the
  # type; the ID stays phase 1's and this is its cross-reference row.
  test "compares its body by value, so two requests over equal bodies are equal" do
    first = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                   headers: Dexpace::Headers::EMPTY,
                                   body: Dexpace::Body.bytes("héllo"),)
    same = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                  headers: Dexpace::Headers::EMPTY,
                                  body: Dexpace::Body.bytes("héllo"),)
    other = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                   headers: Dexpace::Headers::EMPTY,
                                   body: Dexpace::Body.bytes("wörld"),)

    assert_equal(first, same)
    assert_equal(first.hash, same.hash)
    refute_equal(first, other)
  end

  test "a request carrying a body works as a Hash key, which needs eql? and hash together" do
    key = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                 headers: Dexpace::Headers::EMPTY,
                                 body: Dexpace::Body.bytes("héllo"),)
    twin = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                  headers: Dexpace::Headers::EMPTY,
                                  body: Dexpace::Body.bytes("héllo"),)

    assert_equal(:found, { key => :found }[twin])
  end

  # A stream-backed body compares by identity, correctly: two requests over two different live
  # streams are two different requests, even when the streams hold the same bytes.
  test "two requests over two different stream bodies are not equal" do
    first = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                   headers: Dexpace::Headers::EMPTY,
                                   body: Dexpace::Body.stream(StringIO.new(+"a")),)
    second = Dexpace::Request.build(method: Dexpace::Method::POST, url: "https://example.test/",
                                    headers: Dexpace::Headers::EMPTY,
                                    body: Dexpace::Body.stream(StringIO.new(+"a")),)

    refute_equal(first, second)
  end

  # HTTP-2, HTTP-4, HTTP-18, HTTP-47, XCUT-18: what `.build` owes a caller who never met a
  # Builder. Nested so the file keeps one top-level suite per lib file; these are the proof that
  # the validation lives in the model, where #with and send(:new, ...) also have to meet it.
  class BuildTest < DexpaceTestCase
    def build(**changes)
      Dexpace::Request.build(
        method: "GET", url: "https://example.test/a", headers: Dexpace::Headers::EMPTY, **changes,
      )
    end

    test "build coerces a method token and a URL string into their types" do
      built = build(method: "post", body: nil)

      assert_equal(Dexpace::Method::POST, built.method)
      assert_equal("https://example.test/a", Dexpace::URL.external_form(built.url))
    end

    test "build coerces a method token whose tag is a stateful encoding" do
      built = build(method: "get".encode("ISO-2022-JP"), body: nil)

      assert_equal(Dexpace::Method::GET, built.method)
    end

    test "build rejects a method token, a URL and a headers value it cannot coerce" do
      assert_raises(Dexpace::InvalidArgumentError) { build(method: "GE T") }
      assert_raises(Dexpace::InvalidArgumentError) { build(url: "::bad", body: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { build(headers: {}, body: nil) }
    end

    # HTTP-18 and XCUT-18: a request's headers are caller-set, so they are outbound by
    # definition, and a collection the INBOUND grammar validated admits the obs-text HTTP-18
    # forbids. The direction member is what is checked, not the content: an empty inbound
    # collection is refused too, because #new_builder on it would derive a lenient builder for
    # every later #header.
    test "build and with refuse a Headers validated by the inbound grammar" do
      inbound = Dexpace::Headers.inbound_builder.add("X-Trace", "v\xC3\xA5lue").build
      error = assert_raises(Dexpace::InvalidArgumentError) { build(headers: inbound) }

      assert_includes(error.message, "outbound")
      assert_raises(Dexpace::InvalidArgumentError) { build.with(headers: inbound) }
      assert_raises(Dexpace::InvalidArgumentError) do
        build(headers: Dexpace::Headers::EMPTY_INBOUND)
      end
    end

    test "build names a missing member through the shared required-field helper" do
      %i[method url headers].each do |name|
        error = assert_raises(Dexpace::InvalidArgumentError) { build(name => nil, body: nil) }

        assert_equal("#{name} is required", error.message)
      end
    end

    # HTTP-2's residual gap, asserted rather than papered over (design §10.10, §11.6). `send`
    # bypassing `private` is a documented Ruby feature and cannot be closed; the mitigation is
    # that HTTP-17/HTTP-18 are re-validated at the model-to-wire boundary inside every transport
    # (phase 8a Task 16, phase 8c Task 9), which makes this a correctness-of-shape gap and not a
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
end
