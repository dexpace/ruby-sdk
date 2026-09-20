# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-1 (the page view), PAGE-12, PAGE-14, PAGE-15, PAGE-6's probe half, PAGE-8's
# two-views half. Up to two live pages can exist at once, which is why the look-ahead slot lives on
# the Walk and not in the enumerator's closure (pagination/9bdf90fc).
class DexpacePagePagesTest < DexpaceTestCase
  include PageFixtures

  def bodies(count) = Array.new(count) { fake_response_body }

  test "PAGE-1: the page view yields exactly one page object per page, with status and headers" do
    pages = paginator_over([[1], [2], [3]]).pages.to_a

    assert_equal(3, pages.size)
    assert_equal([[1], [2], [3]], pages.map(&:items))
    assert_equal(200, pages.first.status.code)
    assert_equal("https://x/i?p=2", Dexpace::URL.external_form(pages.last.request.url))
    assert(pages.all?(&:closed?)) # to_a ran the walk to exhaustion; every page is released
  end

  test "PAGE-12: the previous page is closed as the consumer advances" do
    probes = bodies(3)
    seen = []
    paginator_over([[1], [2], [3]], bodies: probes).each_page do |_page|
      seen << probes.map(&:closes)
    end

    assert_equal([[0, 0, 0], [1, 0, 0], [1, 1, 0]], seen)
  end

  test "PAGE-12: the last page is closed at exhaustion" do
    probes = bodies(2)

    paginator_over([[1], [2]], bodies: probes).each_page { |page| refute_predicate(page, :closed?) }

    assert_equal([1, 1], probes.map(&:closes))
  end

  test "PAGE-12: probing without advancing, then closing, releases the prefetched page" do
    probes = bodies(2)
    view = paginator_over([[1], [2]], bodies: probes).pages

    assert_predicate(view, :more?)
    view.close

    assert_equal([1, 0], probes.map(&:closes))
  end

  test "PAGE-12: breaking out of a page loop inside a scoped close releases the held page" do
    probes = bodies(2)
    paginator_over([[1], [2]], bodies: probes).each_page { |page| break if page.items == [1] }

    assert_equal([1, 0], probes.map(&:closes))
  end

  test "PAGE-6 / PAGE-12: a second probe costs no exchange and strands no page" do
    probes = bodies(3)
    paginator = paginator_over([[1], [2], [3]], bodies: probes)
    view = paginator.pages

    assert_predicate(view, :more?)
    assert_predicate(view, :more?) # reads the staged page; MUST NOT fetch a second one

    assert_equal(1, paginator.transport.calls.size)
    view.close

    assert_equal([1, 0, 0], probes.map(&:closes)) # nothing was displaced unclosed
  end

  test "PAGE-12: a probed page is the one then yielded; a probe inside the loop stages the next" do
    probes = bodies(3)
    view = paginator_over([[1], [2], [3]], bodies: probes).pages
    view.more?
    yielded = []
    view.each do |page|
      yielded << page.items
      view.more?
    end

    assert_equal([[1], [2], [3]], yielded)
    assert_equal([1, 1, 1], probes.map(&:closes))
  end

  test "PAGE-12: probing an exhausted-and-closed view fetches nothing and strands nothing" do
    probes = bodies(2)
    paginator = paginator_over([[1]], bodies: probes)
    view = paginator.pages
    view.each { |_page| :consumed } # drives to exhaustion; the ensure closes the walk

    refute_predicate(view, :more?)
    assert_equal(1, paginator.transport.calls.size)
    assert_equal([1, 0], probes.map(&:closes))
  end

  test "PAGE-6: constructing the view fetches nothing; more? on an empty stream answers false" do
    paginator = paginator_over([[]], strategy: Class.new do
      def parse(_response, _template) = Dexpace::Page::Info.terminal
    end.new,)
    view = paginator.pages

    assert_equal(0, paginator.transport.calls.size)
    assert_predicate(view, :more?) # the empty terminal page is still one page
    assert_equal(1, paginator.transport.calls.size)
  end

  # PAGE-15's surfaced close failures, on the advance and on the explicit close.
  class SurfacedCloseTest < DexpaceTestCase
    include PageFixtures

    def bodies(count) = Array.new(count) { fake_response_body }

    test "PAGE-15: a close error while ADVANCING is surfaced, not swallowed" do
      probes = [fake_response_body(close_error: IOError.new("advance")), fake_response_body]
      seen = []

      error = assert_raises(IOError) do
        paginator_over([[1], [2]], bodies: probes).each_page { |page| seen << page.items }
      end

      assert_equal("advance", error.message)
      assert_equal([[1]], seen)
      assert_equal([1, 1], probes.map(&:closes)) # the ensure released the page held at the raise
    end

    test "PAGE-15: a close error while releasing a held page is SURFACED, not swallowed" do
      body = fake_response_body(close_error: IOError.new("boom"))
      view = paginator_over([[1]], bodies: [body]).pages

      assert_predicate(view, :more?)
      assert_raises(IOError) { view.close }
      assert_predicate(view, :closed?)
      # The walk cleared its slots BEFORE the raise (R1-1): the closed view neither reports the
      # page whose close failed nor hands it out; a drive over the closed walk yields nothing.
      refute_predicate(view, :more?)
      view.each { |page| flunk("a closed view yielded a page: #{page.items.inspect}") }
    end
  end

  # PAGE-14's single-use latch, PAGE-8's two-views rule, PAGE-13 through the view, construction.
  class SingleUseTest < DexpaceTestCase
    include PageFixtures

    def bodies(count) = Array.new(count) { fake_response_body }

    test "PAGE-14: the iterator may be obtained at most once; re-iteration fails" do
      view = paginator_over([[1]]).pages
      view.each { |_page| :consumed }

      error = assert_raises(Dexpace::Page::PageStateError) { view.each { |_page| :again } }

      assert_match(/single-use/, error.message)
      assert_raises(Dexpace::Page::PageStateError) { view.each }
      assert_raises(Dexpace::Page::PageStateError) { view.to_a }
    end

    test "PAGE-14: a block-less #each latches too -- the Enumerator IS the one iteration" do
      view = paginator_over([[1]]).pages
      enumerator = view.each

      assert_kind_of(Enumerator, enumerator)
      assert_raises(Dexpace::Page::PageStateError) { view.each { |_page| :again } }
      assert_equal([1], enumerator.next.items)
    end

    test "PAGE-8: two separate views from one paginator each drive a full fetch sequence" do
      paginator = paginator_over([[1], [2]], sequences: 2)
      paginator.pages.to_a
      paginator.pages.to_a

      assert_equal(4, paginator.transport.calls.size)
    end

    test "PAGE-13: a parse failure propagates out of the page view, the held page released" do
      probes = bodies(2)
      strategy = Class.new do
        define_method(:parse) do |response, template|
          raise KeyError, "second" if response.request.url.query == "p=1"

          PageFixtures::ScriptedStrategy.new([[1], [2]]).parse(response, template)
        end
      end.new
      paginator = paginator_over([[1], [2]], bodies: probes, strategy: strategy)

      assert_raises(KeyError) { paginator.each_page { |_page| :consumed } }
      assert_equal([1, 1], probes.map(&:closes))
    end

    test "the view is engine-constructed and closes idempotently" do
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Page::Pages.new(nil) }
      view = paginator_over([[1]]).pages

      assert_nil(view.close)
      assert_nil(view.close)
      assert_predicate(view, :closed?)
    end
  end
end
