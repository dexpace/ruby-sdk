# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-6 (the blocking engine's half, R10), PAGE-8 (the engine half), PAGE-9, PAGE-10,
# PAGE-36, PIPE-26 / PIPE-27 (a pipeline is a transport the paginator never closes); HTTP-3 /
# HTTP-4 for the construction pattern.
class DexpacePagePaginatorTest < DexpaceTestCase
  include PageFixtures

  test "PAGE-6 (blocking engine): construction and obtaining a view trigger ZERO exchanges" do
    paginator = paginator_over([[1]])

    assert_equal(0, paginator.transport.calls.size)
    paginator.items

    assert_equal(0, paginator.transport.calls.size)
    paginator.items.to_enum(:each)

    assert_equal(0, paginator.transport.calls.size)
    paginator.pages

    assert_equal(0, paginator.transport.calls.size)
    paginator.pages.each

    assert_equal(0, paginator.transport.calls.size)
  end

  test "PAGE-6: exactly one exchange per page actually consumed" do
    paginator = paginator_over([[1], [2], [3]])

    assert_equal([1], paginator.items.first(1))
    assert_equal(1, paginator.transport.calls.size)
    assert_equal([1, 2], paginator.items.first(2))
    assert_equal(3, paginator.transport.calls.size)
  end

  test "PAGE-9: the cap is validated strictly positive AT CONSTRUCTION, not lazily" do
    [0, -1, 0.0, -0.5, Float::NAN, nil, "3", :three].each do |cap|
      error = assert_raises(Dexpace::InvalidArgumentError) { paginator_over([[1]], cap: cap) }

      assert_match(/PAGE-9/, error.message, cap.inspect)
    end
    assert_equal(3, paginator_over([[1]], cap: 3).cap)
    assert_in_delta(2.5, paginator_over([[1]], cap: 2.5).cap)
  end

  test "PAGE-9: the cap bounds a server that never advances, counted in exchanges, not items" do
    transport = ScriptedTransport.new(page_script(50))
    paginator = paginator_over([], transport: transport, strategy: EndlessStrategy.new, cap: 3)

    assert_equal([1, 1, 1], paginator.items.to_a)
    assert_equal(3, transport.calls.size)
    assert_equal(3, paginator.pages.count)
    assert_equal(6, transport.calls.size)
  end

  test "PAGE-9: #with re-validates the cap on every interpreter, not only Data#with's" do
    paginator = paginator_over([[1]])

    assert_equal(5, paginator.with(cap: 5).cap)
    assert_raises(Dexpace::InvalidArgumentError) { paginator.with(cap: 0) }
  end

  test "PAGE-10: the default cap is effectively unbounded" do
    assert_equal(Float::INFINITY, paginator_over([[1]]).cap)
    # 600 single-item pages, no cap set: every one is walked. The number is the fixture's own and
    # the two must match, or the assertion is testing the fixture rather than the cap.
    assert_equal(600, paginator_over(Array.new(600) { [1] }).items.count)
  end

  test "PAGE-8: the engine holds only immutable configuration and is safe to share" do
    paginator = paginator_over([[1], [2]], sequences: 2)

    assert_predicate(paginator, :frozen?)
    assert_empty(paginator.instance_variables)
    assert_equal(%i[transport template strategy cap options], paginator.members)
    assert_equal([[1, 2], [1, 2]], [paginator.items.to_a, paginator.items.to_a])
  end

  test "PAGE-8: two threads share one engine and each drives its own full sequence" do
    paginator = paginator_over([[1], [2]], sequences: 2)
    results = Array.new(2) { ::Thread.new { paginator.items.to_a } }.map(&:value)

    assert_equal([[1, 2], [1, 2]], results)
    assert_equal(4, paginator.transport.calls.size)
  end

  test "PAGE-36: the default is no overrides, and a configured override reaches every exchange" do
    assert_same(Dexpace::RequestOptions::EMPTY, paginator_over([[1]]).options)
    options = Dexpace::RequestOptions.builder.tap { |b| b.timeout = 1.5 }.build
    paginator = paginator_over([[1], [2], [3]], options: options)
    paginator.items.to_a

    assert_equal(3, paginator.transport.calls.size)
    paginator.transport.calls.each { |(_request, opts, _cancellation)| assert_same(options, opts) }
  end

  test "PIPE-26 / PIPE-27: a standard pipeline is a transport, and the paginator never closes it" do
    # The object a generated client hands in: Pipeline.standard over a scripted transport, end to
    # end through the redirect, retry and logging steps -- which is also where a nil cancellation
    # would die inside the retry step (P7-102).
    downstream = scripted_transport([[1], [2]])
    pipeline = Dexpace::Pipeline.standard(downstream)
    paginator = paginator_over([[1], [2]], transport: pipeline)

    assert_equal([1, 2], paginator.items.to_a)
    assert_equal(2, downstream.calls.size)
    refute_predicate(pipeline, :closed?)
    downstream.calls.each do |(_request, options, cancellation)|
      assert_equal([Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none],
                   [options, cancellation],)
    end
  end

  test "HTTP-4: every member is validated and named" do
    assert_raises(Dexpace::InvalidArgumentError) { paginator_over([[1]], transport: :not_callable) }
    assert_raises(Dexpace::InvalidArgumentError) { paginator_over([[1]], template: "https://x/") }
    assert_raises(Dexpace::InvalidArgumentError) { paginator_over([[1]], strategy: Object.new) }
    assert_raises(Dexpace::InvalidArgumentError) { paginator_over([[1]], options: { timeout: 1 }) }
    refute_respond_to(Dexpace::Page::Paginator, :new)
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Page::Paginator.build(transport: scripted_transport([]), template: nil,
                                     strategy: EndlessStrategy.new,)
    end

    assert_equal("template is required", error.message)
  end

  test "the scoped openers require a block and close the walk on every exit" do
    paginator = paginator_over([[1], [2]])

    assert_raises(Dexpace::InvalidArgumentError) { paginator.each_item }
    assert_raises(Dexpace::InvalidArgumentError) { paginator.each_page }
    items = []

    assert_nil(paginator.each_item { |item| items << item })
    assert_equal([1, 2], items)
  end
end
