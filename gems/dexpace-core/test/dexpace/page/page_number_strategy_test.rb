# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-17 and PAGE-5 (asserted). The empty-items check runs FIRST and is defensive
# against servers that return an empty page past the end; the current page is inferred from the
# ORIGINATING (executed) request, which in this port is response.request -- not the template.
class DexpacePagePageNumberStrategyTest < DexpaceTestCase
  include PageFixtures

  Strategy = Dexpace::Page::PageNumberStrategy

  def strategy(items, **keywords)
    Strategy.build(extract_items: ->(_r) { items }, **keywords)
  end

  def executed(url) = page_response(request: fake_request(url: url))

  test "PAGE-17: first page with no param and non-empty items -> next request page=start+1" do
    info = strategy([1]).parse(executed("https://x/i"), fake_request(url: "https://x/i"))

    assert_equal("page=2", info.next_request.url.query)
    assert_equal([1], info.items)
  end

  test "PAGE-17: an empty items list is end-of-stream, checked before anything else" do
    info = strategy([]).parse(executed("https://x/i?page=4"), fake_request)

    assert_nil(info.next_request)
    assert_empty(info.items)
  end

  test "PAGE-17: a garbage, empty, negative, fractional or absent page value computes from start" do
    # %D9%A3 is the Arabic-Indic three, a non-ASCII numeral: [0-9] refuses it where \d might not.
    ["page=abc", "page=", "", "page=-2", "page=1.5", "page=1e3", "page=%D9%A3",
     "page= 1",].each do |query|
      info = strategy([1], start: 7).parse(executed("https://x/i?#{query}"), fake_request(url: "https://x/i"))

      assert_equal("page=8", info.next_request.url.query, query)
    end
  end

  test "PAGE-22: the page value is read DECODED, so a percent-encoded number is a number" do
    info = strategy([1], start: 7).parse(executed("https://x/i?page=%31%32"), fake_request(url: "https://x/i"))

    assert_equal("page=13", info.next_request.url.query)
  end

  test "PAGE-17: the parameter name and the start page are both configurable, 0-based allowed" do
    info = strategy([1], parameter: "pageNumber", start: 0)
      .parse(executed("https://x/i"), fake_request(url: "https://x/i"))

    assert_equal("pageNumber=1", info.next_request.url.query)
    assert_equal(["page", 1], [strategy([1]).parameter, strategy([1]).start])
  end

  test "PAGE-17: the current page is read from the EXECUTED request, not the template" do
    info = strategy([1]).parse(executed("https://x/i?page=5"), fake_request(url: "https://x/i?page=1"))

    assert_equal("page=6", info.next_request.url.query)
  end

  test "PAGE-17: the next request is the TEMPLATE with its page spliced; the rest survives" do
    template = fake_request(url: "https://x/i?filter=a:b&page=1&sort=asc", method: "POST",
                            body: fake_body,)
    info = strategy([1]).parse(executed("https://x/i?filter=a:b&page=1&sort=asc"), template)

    assert_equal("filter=a:b&page=2&sort=asc", info.next_request.url.query)
    assert_same(template.body, info.next_request.body)
    assert_equal(template.method, info.next_request.method)
  end

  test "PAGE-5: parse closes nothing, mutates nothing, retains nothing; the strategy is frozen" do
    response = executed("https://x/i")
    subject = strategy([1])
    subject.parse(response, fake_request)

    assert_equal(0, closes_of(response))
    assert_empty(subject.instance_variables)
    assert_predicate(subject, :frozen?)
  end

  test "PAGE-4: an extractor that raises is a parse failure; a non-Array answer is refused" do
    assert_raises(KeyError) do
      Strategy.build(extract_items: lambda { |_r|
        raise KeyError, "k"
      }).parse(executed("https://x/i"), fake_request)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Strategy.build(extract_items: ->(_r) {}).parse(executed("https://x/i"), fake_request)
    end
  end

  test "HTTP-4: start a non-negative Integer, parameter a non-empty String, extractor callable" do
    assert_raises(Dexpace::InvalidArgumentError) { strategy([1], start: -1) }
    assert_raises(Dexpace::InvalidArgumentError) { strategy([1], start: 1.0) }
    assert_raises(Dexpace::InvalidArgumentError) { strategy([1], parameter: "") }
    assert_raises(Dexpace::InvalidArgumentError) { Strategy.build(extract_items: nil) }
    refute_respond_to(Strategy, :new)
  end

  test "HTTP-4 / P7-107: a present but non-callable extractor is refused by class, not by nil" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Strategy.build(extract_items: :items) }

    assert_match(/extract_items must respond to #call, got Symbol/, error.message)
  end

  test "the digit screen is anchored and carries its own per-pattern timeout" do
    assert_in_delta(1.0, Strategy.const_get(:DIGITS).timeout)
    assert_raises(::NameError) { Strategy::DIGITS }
    assert_equal("page=13",
                 strategy([1]).parse(executed("https://x/i?page=12"),
                                     fake_request,).next_request.url.query,)
    assert_equal("page=8",
                 strategy([1], start: 7).parse(executed("https://x/i?page=12x"),
                                               fake_request,).next_request.url.query,)
  end
end
