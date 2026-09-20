# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"
require_relative "../../support/recording_body"

# Exercises: PAGE-16 and PAGE-5 (asserted), PAGE-4's "never by throwing"; R7 / P7-6.
#
# The strategy takes a caller-supplied #call(response) extractor, NEVER a serializer duck type
# and never a witness -- a keyword naming one would put that word inside lib/dexpace/page/** and
# boundary 5's audit would fail on this sub-phase's own code. PAGE-16's "single read of the
# response body" is therefore the EXTRACTOR's read; core performs none, and the read-counting
# RecordingBody below is what makes that checkable. Every response is a REAL Dexpace::Response.
class DexpacePageCursorStrategyTest < DexpaceTestCase
  include PageFixtures

  Strategy = Dexpace::Page::CursorStrategy

  test "PAGE-16: cursor 'c' derives a next request with cursor=c on the template" do
    strategy = Strategy.build(extract: ->(_r) { [[1, 2], "c"] })
    info = strategy.parse(page_response, fake_request(url: "https://x/i?page=1"))

    assert_equal([1, 2], info.items)
    assert_equal("page=1&cursor=c", info.next_request.url.query)
    assert_equal("c", info.continuation_token)
  end

  test "PAGE-16: a null OR empty next cursor is end-of-stream" do
    [nil, ""].each do |cursor|
      strategy = Strategy.build(extract: ->(_r) { [[1], cursor] })
      info = strategy.parse(page_response, fake_request)

      assert_nil(info.next_request)
      assert_equal([1], info.items)
      assert_nil(info.continuation_token)
    end
  end

  test "PAGE-16: a later cursor REPLACES the earlier one in place, never appends a second" do
    strategy = Strategy.build(extract: ->(_r) { [[], "c2"] })
    info = strategy.parse(page_response, fake_request(url: "https://x/i?cursor=c1&sort=asc"))

    assert_equal("cursor=c2&sort=asc", info.next_request.url.query)
  end

  test "PAGE-16: the configurable parameter name defaults to cursor" do
    assert_equal("cursor", Strategy.build(extract: ->(_r) { [[], nil] }).parameter)
    strategy = Strategy.build(extract: ->(_r) { [[], "c"] }, parameter: "after")
    info = strategy.parse(page_response, fake_request(url: "https://x/i"))

    assert_equal("after=c", info.next_request.url.query)
  end

  test "PAGE-16: core reads the body exactly zero times; the extractor reads it once" do
    body = RecordingBody.new("payload")
    untouched = RecordingBody.new("payload")
    strategy = Strategy.build(extract: lambda { |r|
      r.body.source
      [[], nil]
    })

    strategy.parse(page_response(body: body), fake_request)
    Strategy.build(extract: lambda { |_r|
      [[], nil]
    }).parse(page_response(body: untouched), fake_request)

    assert_equal(1, body.source_count)
    assert_equal(0, untouched.source_count)
    assert_equal(0, untouched.release_count)
  end

  test "PAGE-16: an extractor reading through Response#body_string is single-use by 3b's body" do
    # A real ResponseBody raises Dexpace::ClosedError on a second body_string (measured): the
    # single read is enforced by the body wherever the extractor reads through the decode boundary.
    real = Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes("c".b))
    response = page_response(body: real)
    strategy = Strategy.build(extract: ->(r) { [[], r.body_string] })

    assert_equal("cursor=c", strategy.parse(response, fake_request).next_request.url.query)
    assert_raises(Dexpace::ClosedError) { strategy.parse(response, fake_request) }
  end

  test "PAGE-5: parse closes nothing, mutates nothing, and the strategy retains nothing" do
    response = page_response
    strategy = Strategy.build(extract: ->(_r) { [[], nil] })
    strategy.parse(response, fake_request)

    assert_equal(0, closes_of(response))
    assert_empty(strategy.instance_variables) # a Data holds no ivars at all (measured)
    assert_predicate(strategy, :frozen?)
  end

  test "PAGE-5: one instance serves two walks with different templates and responses" do
    strategy = Strategy.build(extract: ->(r) { [[r.status.code], "c"] })
    a = strategy.parse(page_response(status: 200), fake_request(url: "https://a/x"))
    b = strategy.parse(page_response(status: 201), fake_request(url: "https://b/y?q=1"))

    assert_equal([[200], "https://a/x?cursor=c"], [a.items, Dexpace::URL.external_form(a.next_request.url)])
    assert_equal([[201], "https://b/y?q=1&cursor=c"],
                 [b.items, Dexpace::URL.external_form(b.next_request.url)],)
  end

  test "PAGE-4: an extractor that raises is a parse failure, not an end-of-stream signal" do
    strategy = Strategy.build(extract: ->(_r) { raise KeyError, "no items" })

    assert_raises(KeyError) { strategy.parse(page_response, fake_request) }
  end

  test "the extractor's answer is validated: a pair, items an Array, cursor a String or nil" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Strategy.build(extract: ->(_r) { [1] }).parse(page_response, fake_request)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Strategy.build(extract: ->(_r) { "items" }).parse(page_response, fake_request)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Strategy.build(extract: ->(_r) { [nil, "c"] }).parse(page_response, fake_request)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Strategy.build(extract: ->(_r) { [[], 42] }).parse(page_response, fake_request)
    end
  end

  test "HTTP-3 / HTTP-4: .build validates, .new is private, #with re-validates" do
    assert_raises(Dexpace::InvalidArgumentError) { Strategy.build(extract: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Strategy.build(extract: :not_callable) }
    assert_raises(Dexpace::InvalidArgumentError) { Strategy.build(extract: ->(_r) {}, parameter: "") }
    assert_raises(Dexpace::InvalidArgumentError) { Strategy.build(extract: ->(_r) {}, parameter: 1) }
    refute_respond_to(Strategy, :new)

    strategy = Strategy.build(extract: ->(_r) { [[], nil] })

    assert_equal("after", strategy.with(parameter: "after").parameter)
    assert_raises(Dexpace::InvalidArgumentError) { strategy.with(parameter: nil) }
  end
end
