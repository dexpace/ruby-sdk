# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/page_fixtures"

# Exercises: PAGE-2, PAGE-3, PAGE-19 (.next_request_from, the reusable branch), PAGE-23, PAGE-34
# (the two keys' shape); P7-2, P7-5, P7-101, P7-104, P7-107, P7-117.
#
# A Page is a plain class including Dexpace::Closeable and NOT a Data, because a Data instance is
# frozen and cannot hold the latch (phase 3b's finding, applied one layer up). Response#close is a
# pure forward with no latch of its own, and Response#body may be nil or a BufferBody whose #close
# is a documented no-op -- so PAGE-27's exactly-once cannot be delegated to the response. Every
# response below is a REAL Dexpace::Response over a FakeResponseBody, whose UN-latched #closes
# counter is what makes the page's own latch observable.
class DexpacePageTest < DexpaceTestCase
  include PageFixtures

  test "PAGE-3: closing the page releases the response exactly once, however many times called" do
    response = page_response
    page = Dexpace::Page.build(response: response, items: [1, 2])

    page.close
    page.close
    page.close

    assert_equal(1, closes_of(response))
    assert_predicate(page, :closed?)
    assert_predicate(page, :owned?)
  end

  test "PAGE-2: items, status, headers and request stay readable after close" do
    request = fake_request(url: "https://x/i?p=3")
    response = page_response(request: request, status: 201, headers: { "x-a" => "1" })
    page = Dexpace::Page.build(response: response, items: [1, 2])
    page.close

    assert_equal([1, 2], page.items)
    assert_equal(201, page.status.code)
    assert_equal(["1"], page.headers["x-a"])
    assert_same(request, page.request)
    assert_same(response, page.response)
  end

  test "PAGE-2: items are never nil, MAY be empty, are frozen; the elements stay the caller's" do
    element = Object.new
    source = [element]
    page = Dexpace::Page.build(response: page_response, items: source)
    source << Object.new

    assert_equal([element], page.items)
    assert_predicate(page.items, :frozen?)
    assert_same(element, page.items.first) # shallow: never Model.own's deep copy (P7-101)
    refute_predicate(element, :frozen?)
    assert_empty(Dexpace::Page.build(response: page_response, items: []).items)
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Page.build(response: page_response, items: nil)
    end
  end

  test "PAGE-3: a close error propagates once and the latch stays flipped" do
    response = page_response(close_error: RuntimeError.new("boom"))
    page = Dexpace::Page.build(response: response, items: [])

    assert_raises(RuntimeError) { page.close }
    assert_predicate(page, :closed?)
    page.close # no second release attempted

    assert_equal(1, closes_of(response))
  end

  test "the page takes a real Response and nothing shaped like one; .new is private" do
    duck = Struct.new(:status, :headers, :request, :close).new

    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Page.build(response: duck, items: []) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Page.build(response: nil, items: []) }
    refute_respond_to(Dexpace::Page, :new)
  end

  test "PAGE-2 / P7-107: items must be an Array; an Enumerable that is not one is refused" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Page.build(response: page_response, items: (1..3))
    end

    assert_match(/items must be an Array, got Range/, error.message)
  end

  test "spec-forced boundary 5: no serializer token under lib/dexpace/page, comments included" do
    # 7b's serde-boundary scan (its Task 11) does not strip comments, so the two bare tokens it
    # refuses must appear nowhere -- not in YARD, not in a string. This is 7c's own guard until
    # that gate moves the page/ row from PENDING to GUARDED (P7-108).
    root = File.expand_path("../../lib/dexpace", __dir__)
    files = Dir.glob("page/**/*.rb", base: root) + ["page.rb"]
    banned = /(?<![A-Za-z_:])(?:::)?(?:Dexpace::Serde|Serde|JSON)\b/
    offenders = files.select { |name| File.read(File.join(root, name)).match?(banned) }

    assert_equal(15, files.size)
    assert_empty(offenders)
  end

  test "PAGE-34's two keys travel from .build to the readers" do
    page = Dexpace::Page.build(response: page_response, items: [], next_link: "L",
                               continuation_token: "T",)

    assert_equal(%w[L T], [page.next_link, page.continuation_token])
  end

  test "PAGE-34 / P7-107: a key that is neither nil nor a String is named and refused at .build" do
    # The same rule Info applies to the same two members: a fetcher's page carrying an Integer link
    # is the caller's mistake, named here, never a NoMethodError in the front-end's key_of.
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Page.build(response: page_response, items: [], next_link: 42)
    end
    token = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Page.build(response: page_response, items: [], continuation_token: :t)
    end

    assert_match(/next_link must be a String or nil, got Integer/, error.message)
    assert_match(/continuation_token must be a String or nil, got Symbol/, token.message)
  end

  test "XCUT-15: the two keys are copied frozen; the caller's String stays the caller's" do
    link = +"L"
    page = Dexpace::Page.build(response: page_response, items: [], next_link: link,
                               continuation_token: +"T",)

    assert_predicate(page.next_link, :frozen?)
    assert_predicate(page.continuation_token, :frozen?)
    refute_same(link, page.next_link)
    refute_predicate(link, :frozen?)
    assert_equal("L", page.next_link)
  end

  # PAGE-19's reusable branch, public so a caller-written strategy reaches the two end-of-stream
  # rules for a BODY-derived next URL rather than re-deriving them (P7-2).
  class NextRequestFromTest < DexpaceTestCase
    include PageFixtures

    BASE = "https://x/v1/items?page=1"

    def next_request(target, template: fake_request(url: BASE))
      response = page_response(request: fake_request(url: BASE))
      Dexpace::Page.next_request_from(template, response, target)
    end

    test "PAGE-19: a query-only target keeps the path; an absolute and a relative one resolve" do
      assert_equal("https://x/v1/items?page=2", Dexpace::URL.external_form(next_request("?page=2").url))
      assert_equal("https://other/y", Dexpace::URL.external_form(next_request("https://other/y").url))
      assert_equal("https://x/v1/next", Dexpace::URL.external_form(next_request("next").url))
    end

    test "PAGE-19: an unresolvable target is end-of-stream, never an exception" do
      assert_nil(next_request("not a url"))
      assert_nil(next_request("http://[bad"))
    end

    test "P7-5: a nil, blank or whitespace-only target is end-of-stream BEFORE resolution" do
      assert_nil(next_request(nil))
      assert_nil(next_request(""))
      assert_nil(next_request("   "))
      assert_nil(next_request("\t\n"))
    end

    test "P7-117: a fragment-only target is same-document and end-of-stream, like the empty one" do
      # RFC 3986 §4.4 names the empty reference and the fragment-only one together: join resolves
      # "#x" to the base plus a fragment the wire never carries, so without the guard a server
      # emitting <#>; rel=next would be re-fetched until the page cap (review round 1's R1-2).
      assert_nil(next_request("#"))
      assert_nil(next_request("#top"))
      assert_nil(next_request(" #x "))
      # Deliberately NOT screened -- the check is syntactic, never on the resolved URL: a target
      # that reaches the current page by another spelling is a next request PAGE-9's cap bounds.
      assert_equal("https://x/v1/items?", Dexpace::URL.external_form(next_request("?").url))
      assert_equal(BASE, Dexpace::URL.external_form(next_request("//").url))
      assert_equal(BASE, Dexpace::URL.external_form(next_request(BASE).url))
    end

    test "P7-104: a target this client cannot dispatch is end-of-stream, as REDIR-18 screens" do
      # Every one of these is a SUCCESSFUL URI::RFC3986_PARSER.join (6b's P6-95): a mailto:, a
      # javascript:, a host-less http:foo and an empty-host http:///p. Without the screen each would
      # become a Request the transport then fails on, which is an error where PAGE-19 wants an end.
      assert_nil(next_request("mailto:a@b"))
      assert_nil(next_request("javascript:alert(1)"))
      assert_nil(next_request("http:foo"))
      assert_nil(next_request("http:///p"))
      assert_nil(next_request("ftp://h/z"))
      refute_nil(next_request("HTTPS://h/z")) # the scheme screen folds without a locale
    end

    test "PAGE-23: the template's method, headers and body travel; only the URL changes" do
      template = fake_request(url: BASE, method: "POST", headers: { "x-a" => "1" }, body: fake_body)
      nxt = next_request("?page=2", template: template)

      assert_equal(template.method, nxt.method)
      assert_equal(template.headers, nxt.headers)
      assert_same(template.body, nxt.body)
      refute_equal(Dexpace::URL.external_form(template.url), Dexpace::URL.external_form(nxt.url))
    end

    test "PAGE-19: the base is the RESPONSE's request URL, not the template's" do
      template = fake_request(url: "https://template/only?page=0")
      response = page_response(request: fake_request(url: "https://final/hop/list?page=3"))

      nxt = Dexpace::Page.next_request_from(template, response, "?page=4")

      assert_equal("https://final/hop/list?page=4", Dexpace::URL.external_form(nxt.url))
    end
  end
end
