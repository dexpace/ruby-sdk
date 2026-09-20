# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-5 (enforced), PAGE-7, PAGE-9, PAGE-13, PAGE-15, PAGE-36 -- through the
# private_constant Walk over the Paginator's private per-walk Drive, reached the way 4c's
# cursor_test reaches its private cursor.
#
# The Walk is the object phase 3's Enumerator rule forces into existence: an Enumerator abandoned
# mid-#next never runs its ensure, and neither does an ordinary #each -- and block_given? is TRUE
# inside #each when reached through to_enum(:each), so no in-method guard helps. The only defence is
# where the resource lives, and it lives here (pagination/318ae05d, pagination/b2a85752).
class DexpacePageWalkTest < DexpaceTestCase
  include PageFixtures

  test "PAGE-7: after a terminal page, repeated probes perform no further exchange" do
    paginator = paginator_over([[1], [2]])
    walk = walk_over(paginator)

    2.times { walk.fetch_next_page.close }

    3.times { assert_nil(walk.fetch_next_page) }

    assert_equal(2, paginator.transport.calls.size)
  end

  test "PAGE-9: with a server echoing one cursor forever and cap=N, exactly N exchanges" do
    transport = ScriptedTransport.new(page_script(20))
    paginator = paginator_over([], transport: transport, strategy: EndlessStrategy.new, cap: 3)
    walk = walk_over(paginator)

    pages = Array.new(4) { walk.fetch_next_page }

    assert_equal(3, transport.calls.size)
    assert_equal(3, pages.compact.size)
    assert_nil(pages.last)
    pages.compact.each(&:close)
  end

  test "PAGE-36: the per-call overrides reach EVERY page request, not just the first" do
    options = Dexpace::RequestOptions.build(timeout: 1.5, max_retries: 0, tags: { "t" => "v" })
    paginator = paginator_over([[1], [2], [3]], options: options)
    walk = walk_over(paginator)

    3.times { walk.fetch_next_page.close }

    assert_equal(3, paginator.transport.calls.size)
    paginator.transport.calls.each { |(_request, opts, _cancellation)| assert_same(options, opts) }
  end

  test "P7-102: the sync engine passes Cancellation.none to the transport, never nil" do
    paginator = paginator_over([[1]])
    walk_over(paginator).fetch_next_page.close

    assert_same(Dexpace::Cancellation.none, paginator.transport.calls.first.last)
  end

  test "PAGE-13: a throwing parse closes the response inline exactly once and propagates" do
    body = fake_response_body
    paginator = paginator_over([[1]], bodies: [body], strategy: raising_strategy(KeyError.new("k")))
    walk = walk_over(paginator)

    assert_raises(KeyError) { walk.fetch_next_page }
    assert_equal(1, body.closes)
    assert_nil(walk.current)
    assert_nil(walk.buffered)
  end

  test "PAGE-13: a close failure does NOT mask the parse failure; it is attached as suppressed" do
    body = fake_response_body(close_error: IOError.new("close boom"))
    paginator = paginator_over([[1]], bodies: [body], strategy: raising_strategy(KeyError.new("k")))
    walk = walk_over(paginator)

    error = assert_raises(KeyError) { walk.fetch_next_page }

    assert_equal("k", error.message)
    assert_equal([IOError], Dexpace.suppressed(error).map(&:class))
    assert_equal(1, body.closes)
  end

  test "PAGE-13: a fatal-family parse failure still closes the response, and carries no trail" do
    body = fake_response_body(close_error: IOError.new("close boom"))
    paginator = paginator_over([[1]], bodies: [body],
                                      strategy: raising_strategy(NoMemoryError.new("f")),)
    walk = walk_over(paginator)

    error = assert_raises(NoMemoryError) { walk.fetch_next_page }

    assert_equal(1, body.closes)
    assert_empty(Dexpace.suppressed(error))
  end

  test "PAGE-13 / P7-107: a parse answering something other than an Info is refused and closed" do
    body = fake_response_body
    not_info = Class.new { def parse(_response, _template) = [[1], nil] }.new
    walk = walk_over(paginator_over([[1]], bodies: [body], strategy: not_info))

    error = assert_raises(Dexpace::InvalidArgumentError) { walk.fetch_next_page }

    assert_match(/parse must return a Dexpace::Page::Info, got Array/, error.message)
    assert_equal(1, body.closes)
  end

  # The two slots, their release discipline and the walk's own latch (PAGE-12, PAGE-15).
  class SlotsTest < DexpaceTestCase
    include PageFixtures

    test "PAGE-15: #close releases BOTH the held page and the buffered page" do
      a = fake_response_body
      b = fake_response_body
      walk = walk_over(paginator_over([[1], [2]], bodies: [a, b]))
      walk.hold(walk.fetch_next_page)
      walk.buffer(walk.fetch_next_page)

      walk.close

      assert_equal([1, 1], [a.closes, b.closes])
      assert_nil(walk.current)
      assert_nil(walk.buffered)
      assert_predicate(walk, :closed?)
    end

    test "PAGE-15: both held pages fail to close -> the first propagates, the second suppressed" do
      first = fake_response_body(close_error: IOError.new("first"))
      second = fake_response_body(close_error: IOError.new("second"))
      walk = walk_over(paginator_over([[1], [2]], bodies: [first, second]))
      walk.hold(walk.fetch_next_page)
      walk.buffer(walk.fetch_next_page)

      error = assert_raises(IOError) { walk.close }

      assert_equal("first", error.message)
      assert_equal(["second"], Dexpace.suppressed(error).map(&:message))
      assert_equal([1, 1], [first.closes, second.closes])
      assert_nil(walk.current) # both slots cleared BEFORE the raise, so the latch and the slots
      assert_nil(walk.buffered) # agree: nothing still references a page whose close failed (R1-1)
      walk.close # the latch is flipped; no second release

      assert_equal([1, 1], [first.closes, second.closes])
    end

    test "PAGE-15 / PAGE-12: the advance close in #hold is SURFACED; the new page is held first" do
      first = fake_response_body(close_error: IOError.new("advance"))
      second = fake_response_body
      walk = walk_over(paginator_over([[1], [2]], bodies: [first, second]))
      walk.hold(walk.fetch_next_page)
      page_two = walk.fetch_next_page

      assert_raises(IOError) { walk.hold(page_two) }
      assert_same(page_two, walk.current) # held BEFORE the previous close: a raise strands nothing
      walk.close

      assert_equal([1, 1], [first.closes, second.closes])
    end

    test "PAGE-12 / PAGE-6: the look-ahead is one slot and a staged page is never displaced" do
      a = fake_response_body
      b = fake_response_body
      walk = walk_over(paginator_over([[1], [2]], bodies: [a, b]))
      staged = walk.fetch_next_page
      walk.buffer(staged)
      extra = walk.fetch_next_page

      assert_raises(Dexpace::Page::PageStateError) { walk.buffer(extra) }
      assert_same(staged, walk.buffered)
      assert_same(staged, walk.take_buffered)
      assert_nil(walk.buffered)
      walk.close
      extra.close
    end

    test "a closed walk fetches nothing, so a late probe acquires no response nothing will close" do
      paginator = paginator_over([[1], [2]])
      walk = walk_over(paginator)
      walk.fetch_next_page.close
      walk.close

      assert_nil(walk.fetch_next_page)
      assert_equal(1, paginator.transport.calls.size)
    end

    test "PAGE-5: the strategy never sees a closed or mutated response" do
      body = fake_response_body
      seen = []
      strategy = Class.new do
        define_method(:parse) do |response, _template|
          seen << response.body.closes
          Dexpace::Page::Info.terminal(items: [])
        end
      end.new
      walk_over(paginator_over([[1]], bodies: [body], strategy: strategy)).fetch_next_page.close

      assert_equal([0], seen)
    end

    test "the walk owns its slots and is a private_constant; Drive is Paginator's, private" do
      assert_raises(::NameError) { Dexpace::Page::Walk }
      assert_raises(::NameError) { Dexpace::Page::Paginator::Drive }
      walk = walk_over(paginator_over([[1]]))

      assert_kind_of(Dexpace::Closeable, walk)
      assert_predicate(walk, :owned?)
      refute_predicate(walk, :closed?)
    end
  end
end
