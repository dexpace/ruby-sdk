# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-4, and HTTP-3 / HTTP-4 / SEAM-29 for the model's construction pattern. A
# strategy's parse output MUST always be well-formed (never nil), MUST signal termination ONLY by
# a null next-request -- never by throwing and never via a side channel -- and an empty items list
# paired with a non-null next-request is a VALID NON-TERMINAL page.
class DexpacePageInfoTest < DexpaceTestCase
  include PageFixtures

  Info = Dexpace::Page::Info

  test "PAGE-4: items are never nil, are frozen, and the collection is owned, not the elements" do
    element = Object.new
    source = [element]
    info = Info.build(items: source, next_request: nil)

    assert_equal([element], info.items)
    assert_predicate(info.items, :frozen?)
    assert_same(element, info.items.first) # a shallow copy: the caller's object, un-frozen (P7-101)
    refute_predicate(element, :frozen?)
    source << Object.new

    assert_equal(1, info.items.size) # the model owns its copy
  end

  test "PAGE-4: a nil next_request is the one end-of-stream signal, and .terminal names it" do
    assert_nil(Info.terminal.next_request)
    assert_empty(Info.terminal.items)
    assert_equal([1], Info.terminal(items: [1]).items)
    refute_respond_to(Info.terminal, :terminal?) # no flag, no sentinel: nil is the whole signal
  end

  test "PAGE-4: empty items with a non-nil next_request is a valid NON-terminal page" do
    info = Info.build(items: [], next_request: fake_request)

    assert_empty(info.items)
    refute_nil(info.next_request)
  end

  test "PAGE-4: items must not be nil, and must be an Array" do
    assert_raises(Dexpace::InvalidArgumentError) { Info.build(items: nil, next_request: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Info.build(items: "a", next_request: nil) }
  end

  test "HTTP-4: next_request is nil or a Request, the two PAGE-34 keys nil or a String" do
    assert_raises(Dexpace::InvalidArgumentError) { Info.build(items: [], next_request: "https://x/") }
    assert_raises(Dexpace::InvalidArgumentError) { Info.build(items: [], next_request: nil, next_link: 1) }
    assert_raises(Dexpace::InvalidArgumentError) do
      Info.build(items: [], next_request: nil, continuation_token: :t)
    end
    info = Info.build(items: [], next_request: nil, next_link: "L", continuation_token: "T")

    assert_equal(%w[L T], [info.next_link, info.continuation_token])
    assert_predicate(info.next_link, :frozen?)
  end

  test "HTTP-3: a frozen Data with a private .new and a #with that re-validates" do
    info = Info.terminal(items: [1])

    assert_predicate(info, :frozen?)
    refute_respond_to(Info, :new)
    assert_equal([1, 2], info.with(items: [1, 2]).items)
    assert_raises(Dexpace::InvalidArgumentError) { info.with(items: nil) }
  end
end
