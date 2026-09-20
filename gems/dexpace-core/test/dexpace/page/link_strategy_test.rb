# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-18, PAGE-19, PAGE-20, PAGE-23, PAGE-5 (asserted); P7-5, P7-104, P7-117. The
# grammar itself is link_header_test.rb's; this suite is the resolution, the configurable header
# name and the end-of-stream routes, through Dexpace::Page.next_request_from.
class DexpacePageLinkStrategyTest < DexpaceTestCase
  include PageFixtures

  Strategy = Dexpace::Page::LinkStrategy
  BASE = "https://api.example.com/repo/issues?page=1"

  def parse(link_values, base: BASE, **keywords)
    strategy = Strategy.build(extract_items: ->(_r) { [1] }, **keywords)
    headers = link_values.nil? ? {} : { "Link" => link_values }
    strategy.parse(page_response(request: fake_request(url: base), headers: headers),
                   fake_request(url: base),)
  end

  def url_of(info) = Dexpace::URL.external_form(info.next_request.url)

  test "PAGE-19: a query-only rel=next preserves the base path (RFC 3986, not RFC 2396)" do
    info = parse(["<?page=2>; rel=next"])

    assert_equal("https://api.example.com/repo/issues?page=2", url_of(info))
    assert_equal([1], info.items)
    assert_equal("?page=2", info.next_link)
  end

  test "PAGE-19: an absolute target is used as-is; a relative one resolves against the base" do
    assert_equal("https://other.example/x", url_of(parse(["<https://other.example/x>; rel=next"])))
    assert_equal("https://api.example.com/repo/next", url_of(parse(["<next>; rel=next"])))
  end

  test "PAGE-19: an unresolvable target is end-of-stream, not an exception" do
    assert_nil(parse(["<not a url>; rel=next"]).next_request)
    assert_nil(parse(["<http://[bad>; rel=next"]).next_request)
  end

  test "P7-104: a target this client cannot dispatch is end-of-stream, never a request" do
    %w[mailto:a@b javascript:alert(1) http:foo http:///p].each do |target|
      assert_nil(parse(["<#{target}>; rel=next"]).next_request, target)
    end
  end

  test "P7-5: a blank rel=next target is end-of-stream, not a resolution to the base" do
    # Verified: URI::RFC3986_PARSER.join(base, "") returns the base UNCHANGED, so resolving a blank
    # target would produce a next request identical to the current one and loop until the page cap.
    assert_nil(parse(["<>; rel=next"]).next_request)
    assert_nil(parse(["<   >; rel=next"]).next_request)
  end

  test "P7-117: a fragment-only rel=next target is end-of-stream too; the check is syntactic" do
    # Verified: join(base, "#top") is the base plus a fragment the wire never carries -- RFC 3986
    # §4.4's other same-document form. A target that reaches the current page by another spelling
    # (<?>, <//>, the URL spelled out) is followed and bounded by the cap, never screened.
    assert_nil(parse(["<#>; rel=next"]).next_request)
    assert_nil(parse(["<#top>; rel=next"]).next_request)
    assert_equal(BASE, url_of(parse(["<#{BASE}>; rel=next"])))
  end

  test "PAGE-18: absence of a Link header, or of a rel=next segment, means end-of-stream" do
    assert_nil(parse(nil).next_request)
    assert_nil(parse(["<https://x/9>; rel=last"]).next_request)
    assert_nil(parse(nil).next_link)
  end

  test "PAGE-20: two separate Link headers, one next one last -> next is followed" do
    assert_equal("https://x/2",
                 url_of(parse(["<https://x/9>; rel=last", "<https://x/2>; rel=next"])),)
  end

  test "PAGE-18: the header name is configurable and defaults to Link, matched under the fold" do
    assert_equal("Link", Strategy.build(extract_items: ->(_r) { [1] }).header)
    strategy = Strategy.build(extract_items: ->(_r) { [1] }, header: "X-Links")
    response = page_response(request: fake_request,
                             headers: { "x-links" => ["<https://x/2>; rel=next"] },)

    assert_equal("https://x/2", url_of(strategy.parse(response, fake_request)))
    assert_nil(Strategy.build(extract_items: lambda { |_r|
      [1]
    }).parse(response, fake_request).next_request)
  end

  test "PAGE-23: following a whole next URL swaps only the URL, preserving method/headers/body" do
    template = fake_request(url: BASE, method: "POST", headers: { "x-a" => "1" }, body: fake_body)
    response = page_response(request: template, headers: { "Link" => ["<https://x/2>; rel=next"] })
    nxt = Strategy.build(extract_items: ->(_r) { [1] }).parse(response, template).next_request

    assert_equal(template.method, nxt.method)
    assert_equal(template.headers, nxt.headers)
    assert_same(template.body, nxt.body)
    assert_equal("https://x/2", Dexpace::URL.external_form(nxt.url))
  end

  test "PAGE-5: parse closes nothing, mutates nothing, retains nothing; the strategy is frozen" do
    response = page_response(headers: { "Link" => ["<https://x/2>; rel=next"] })
    strategy = Strategy.build(extract_items: ->(_r) { [1] })
    strategy.parse(response, fake_request)

    assert_equal(0, closes_of(response))
    assert_empty(strategy.instance_variables)
    assert_predicate(strategy, :frozen?)
  end

  test "PAGE-4: an extractor that raises is a parse failure; a non-Array answer is refused" do
    assert_raises(KeyError) do
      Strategy.build(extract_items: lambda { |_r|
        raise KeyError, "k"
      }).parse(page_response, fake_request)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Strategy.build(extract_items: ->(_r) { "x" }).parse(page_response, fake_request)
    end
  end

  test "HTTP-4: the extractor must be callable and the header name a non-empty String" do
    assert_raises(Dexpace::InvalidArgumentError) { Strategy.build(extract_items: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Strategy.build(extract_items: ->(_r) { [] }, header: "") }
    refute_respond_to(Strategy, :new)
  end

  test "HTTP-4 / P7-107: a present but non-callable extractor is refused by class, not by nil" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Strategy.build(extract_items: :items) }

    assert_match(/extract_items must respond to #call, got Symbol/, error.message)
  end
end
