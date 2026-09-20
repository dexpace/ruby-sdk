# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-1 (the item view), PAGE-8 (the item-view half), PAGE-11, PAGE-15 (the eager
# close's surfaced failure).
#
# PAGE-11's eager close is not a convenience: it is what makes the item view safe on a host where an
# abandoned Enumerator's ensure never runs. At every yield point the walk holds nothing open, so the
# residue of pagination/b2a85752 on THIS view is zero.
class DexpacePageItemsTest < DexpaceTestCase
  include PageFixtures

  test "PAGE-1: items are delivered in server order across page boundaries" do
    assert_equal([1, 2, 3, 4, 5], paginator_over([[1, 2], [3, 4], [5]]).items.to_a)
    assert_equal([1, 2, 3, 4, 5], paginator_over([[1, 2], [], [3, 4], [5]]).items.to_a)
  end

  test "PAGE-11: taking one item from a multi-item first page closes it; no second fetch" do
    body = fake_response_body
    paginator = paginator_over([[1, 2], [3]], bodies: [body, fake_response_body])

    paginator.items.each { |item| break if item == 1 }

    assert_equal(1, body.closes)
    assert_equal(1, paginator.transport.calls.size)
  end

  test "PAGE-11: the page is closed BEFORE any of its items is yielded" do
    body = fake_response_body
    observed = paginator_over([[1, 2]], bodies: [body]).items.map { |_item| body.closes }

    assert_equal([1, 1], observed)
  end

  test "PAGE-8: each independent iteration restarts from the initial request with fresh state" do
    paginator = paginator_over([[1], [2]], sequences: 2)
    items = paginator.items

    assert_equal(items.to_a, items.to_a)
    assert_equal(4, paginator.transport.calls.size) # two full fetch sequences
    assert_equal(%w[https://x/i https://x/i?p=1] * 2,
                 paginator.transport.calls.map do |(request, _o, _c)|
                   Dexpace::URL.external_form(request.url)
                 end,)
  end

  test "PAGE-8: two interleaved iterations of ONE view do not share state" do
    paginator = paginator_over([[1], [2], [3]], sequences: 2)
    items = paginator.items
    first = items.to_enum(:each)
    second = items.to_enum(:each)

    assert_equal([1, 1, 2, 2, 3, 3],
                 [first.next, second.next, first.next, second.next, first.next, second.next],)
  end

  test "Enumerable is included, so first, take, lazy and count work with no vocabulary of core's" do
    items = paginator_over([[1, 2], [3, 4], [5]], sequences: 4).items

    assert_kind_of(Enumerable, items)
    assert_equal(1, items.first)
    assert_equal([1, 2, 3], items.take(3))
    assert_equal([2, 4], items.lazy.select(&:even?).first(2))
    assert_equal(5, items.count)
  end

  test "Enumerable#first spends exactly one exchange and closes that page (PAGE-6, PAGE-11)" do
    body = fake_response_body
    paginator = paginator_over([[1, 2], [3]], bodies: [body, fake_response_body])

    assert_equal(1, paginator.items.first)
    assert_equal(1, paginator.transport.calls.size)
    assert_equal(1, body.closes)
  end

  test "Items#close releases nothing, because PAGE-11 left nothing open, and never raises" do
    body = fake_response_body
    items = paginator_over([[1, 2]], bodies: [body]).items
    items.each { |item| break if item == 1 }

    items.close
    items.close

    assert_equal(1, body.closes) # PAGE-11 closed it; #close neither repeats nor adds
    assert_nil(items.close)
  end

  test "external iteration abandoned mid-#next strands nothing: PAGE-11 already closed it" do
    body = fake_response_body
    enumerator = paginator_over([[1, 2]], bodies: [body]).items.to_enum(:each)
    enumerator.next
    GC.start
    GC.start

    assert_equal(1, body.closes)
  end

  test "#each without a block returns an Enumerator that drives nothing until pulled (PAGE-6)" do
    paginator = paginator_over([[1], [2]])
    enumerator = paginator.items.each

    assert_kind_of(Enumerator, enumerator)
    assert_equal(0, paginator.transport.calls.size)
    assert_equal(1, enumerator.next)
    assert_equal(1, paginator.transport.calls.size)
  end

  test "PAGE-15: the eager close's failure is surfaced, unwrapped, with nothing in flight" do
    body = fake_response_body(close_error: IOError.new("eager"))
    error = assert_raises(IOError) { paginator_over([[1]], bodies: [body]).items.to_a }

    assert_equal("eager", error.message)
    assert_instance_of(IOError, error)
  end

  test "PAGE-13: a parse failure propagates out of the item view with the response closed" do
    body = fake_response_body
    paginator = paginator_over([[1]], bodies: [body], strategy: raising_strategy(KeyError.new("k")))

    assert_raises(KeyError) { paginator.items.to_a }
    assert_equal(1, body.closes)
  end

  test "the view is engine-constructed: its opener must be callable" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Page::Items.new(nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Page::Items.new(:walk) }
  end
end
