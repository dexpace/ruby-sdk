# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-34, PAGE-35 (vacuous by construction, design §12's own authority), PAGE-3's
# ownership transfer at a fetcher, and the same two views over the fetcher-driven walk.
class DexpacePageFetchersTest < DexpaceTestCase
  include PageFixtures

  Fetchers = Dexpace::Page::Fetchers
  NEVER = ->(_key) { raise "the next-page fetcher must not be called" }

  test "PAGE-34: the first-page fetcher is called exactly once" do
    calls = 0
    first = lambda do
      calls += 1
      page_with(items: [1])
    end
    front = Fetchers.build(first: first, next_page: NEVER)

    assert_equal([1], front.items.to_a)
    assert_equal(1, calls)
  end

  test "PAGE-34: subsequent pages key off the previous page's next link; next link WINS" do
    keys = []
    next_page = lambda do |key|
      keys << key
      page_with(items: [2])
    end
    first = -> { page_with(items: [1], next_link: "L", continuation_token: "T") }
    front = Fetchers.build(first: first, next_page: next_page)

    assert_equal([1, 2], front.items.to_a)
    assert_equal(["L"], keys)
  end

  test "PAGE-34: with no next link, the continuation token is the fallback" do
    keys = []
    next_page = lambda do |key|
      keys << key
      keys.size == 1 ? page_with(items: [2], next_link: "  ", continuation_token: "T2") : nil
    end
    front = Fetchers.build(first: -> { page_with(items: [1], continuation_token: "T") },
                           next_page: next_page,)

    assert_equal([1, 2], front.items.to_a)
    assert_equal(%w[T T2], keys) # a blank link falls back to the token, both times
  end

  test "PAGE-34: a blank next link with no fallback token ends the stream" do
    spaces = Fetchers.build(first: -> { page_with(items: [1], next_link: "   ") }, next_page: NEVER)
    empty = Fetchers.build(first: -> { page_with(items: [1], next_link: "") }, next_page: NEVER)

    assert_equal([1], spaces.items.to_a)
    assert_equal([1], empty.items.to_a)
  end

  test "PAGE-34: a nil page from either fetcher ends the stream; a nil FIRST page yields empty" do
    assert_empty(Fetchers.build(first: -> {}, next_page: NEVER).items.to_a)
    first = -> { page_with(items: [1], next_link: "L") }
    front = Fetchers.build(first: first, next_page: ->(_key) {})

    assert_equal([1], front.items.to_a)
  end

  test "PAGE-34 / PAGE-3: a fetcher's page owns its response; the front-end closes it" do
    body = fake_response_body
    front = Fetchers.build(first: -> { page_with(items: [1], body: body) }, next_page: ->(_key) {})
    seen = []
    front.each_page { |_page| seen << body.closes }

    assert_equal([0], seen)
    assert_equal(1, body.closes)
  end

  test "PAGE-34: a fetcher's raise propagates through the walk, and a non-Page answer is refused" do
    raising = Fetchers.build(first: -> { raise KeyError, "k" }, next_page: NEVER)
    wrong = Fetchers.build(first: -> { page_response }, next_page: NEVER)

    assert_raises(KeyError) { raising.items.to_a }
    assert_raises(Dexpace::InvalidArgumentError) { wrong.items.to_a }
  end

  # PAGE-35's vacuity, the views over the fetcher-driven walk, and construction.
  class OptionsAndViewsTest < DexpaceTestCase
    include PageFixtures

    Fetchers = Dexpace::Page::Fetchers
    NEVER = ->(_key) { raise "the next-page fetcher must not be called" }

    test "PAGE-35: the SAME options instance is threaded through every fetcher call" do
      options = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 1.0 }.build
      seen = []
      first = lambda do |o|
        seen << o
        page_with(items: [1], next_link: "L")
      end
      next_page = lambda do |_key, o|
        seen << o
        page_with(items: [2])
      end
      front = Fetchers.build(first: first, next_page: next_page, options: options)

      assert_equal([1, 2], front.items.to_a)
      assert_equal(2, seen.size)
      seen.each { |o| assert_same(options, o) }
      assert_same(options, front.options)
    end

    test "PAGE-35: a fetcher that takes no options is called without them; the default is EMPTY" do
      front = Fetchers.build(first: -> { page_with(items: [1]) }, next_page: NEVER)

      assert_equal([1], front.items.to_a)
      assert_same(Dexpace::RequestOptions::EMPTY, front.options)
    end

    test "PAGE-1 / PAGE-12: the page view works over the fetcher-driven walk, look-ahead too" do
      bodies = [fake_response_body, fake_response_body]
      front = Fetchers.build(first: -> { page_with(items: [1], next_link: "L", body: bodies[0]) },
                             next_page: ->(_key) { page_with(items: [2], body: bodies[1]) },)
      view = front.pages

      assert_predicate(view, :more?)
      assert_predicate(view, :more?)
      assert_equal([0, 0], bodies.map(&:closes))
      view.close

      assert_equal([1, 0], bodies.map(&:closes))
      assert_equal([[1], [2]], front.pages.map(&:items))
    end

    test "PAGE-8: the front-end is a frozen Data; each iteration restarts with the first fetcher" do
      firsts = 0
      first = lambda do
        firsts += 1
        page_with(items: [firsts])
      end
      front = Fetchers.build(first: first, next_page: NEVER)

      assert_predicate(front, :frozen?)
      assert_equal([[1], [2]], [front.items.to_a, front.items.to_a])
      assert_equal(2, firsts)
    end

    test "HTTP-4: callable fetchers, RequestOptions options; the openers require a block" do
      assert_raises(Dexpace::InvalidArgumentError) { Fetchers.build(first: nil, next_page: NEVER) }
      assert_raises(Dexpace::InvalidArgumentError) { Fetchers.build(first: :no, next_page: NEVER) }
      assert_raises(Dexpace::InvalidArgumentError) { Fetchers.build(first: -> {}, next_page: :no) }
      assert_raises(Dexpace::InvalidArgumentError) do
        Fetchers.build(first: -> {}, next_page: NEVER, options: {})
      end
      refute_respond_to(Fetchers, :new)
      front = Fetchers.build(first: -> {}, next_page: NEVER)

      assert_raises(Dexpace::InvalidArgumentError) { front.each_item }
      assert_raises(Dexpace::InvalidArgumentError) { front.each_page }
      assert_nil(front.each_item { |_item| flunk("empty") })
    end
  end
end
