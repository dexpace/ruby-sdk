# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-13, PAGE-15, PAGE-32 -- the inversion suite; P7-1, P7-105. No lib/ mirror: it
# asserts the cross-cutting close discipline that no single component suite covers.
#
# MEASURED on 3.2.11, 3.3.12, 3.4.10 and 4.0.6 (matrix_facts_test.rb): a bare `ensure` whose close
# raises while a consumer exception is already in flight REPLACES the consumer's exception as the
# primary (Ruby sets #cause to it). That is the exact inverse of PAGE-13's and PAGE-32's conformance
# clauses, and it is the shape a competent Ruby author writes by default. And the obvious repair --
# reading `$!` at the top of the ensure -- is wrong the other way: `$!` is the CALLER's inside
# anything called from a caller's rescue. Every test below passes under either shape EXCEPT the
# ones marked INVERSION and CALLER'S RESCUE, which are why this file exists.
class DexpacePageLifetimeTest < DexpaceTestCase
  include PageFixtures

  def bounded_value(future) = future.value(deadline: Dexpace::Clock::SYSTEM.monotonic + 5.0)

  test "INVERSION, PAGE-13: consumer raises AND close raises -> the CONSUMER's error is primary" do
    body = fake_response_body(close_error: IOError.new("close"))
    cause = KeyError.new("consumer")

    error = assert_raises(KeyError) do
      paginator_over([[1]], bodies: [body]).each_page { |page| raise cause unless page.nil? }
    end

    assert_same(cause, error)
    assert_equal(["close"], Dexpace.suppressed(error).map(&:message))
    assert_equal(1, body.closes)
  end

  test "INVERSION, PAGE-32 (async): consumer failure stays primary; the close error is swallowed" do
    body = fake_response_body(close_error: IOError.new("close"))
    cause = KeyError.new("consumer")
    future = async_paginator_over([[1]], bodies: [body]).walk(->(_item) { raise cause })

    error = assert_raises(KeyError) { bounded_value(future) }

    assert_same(cause, error)
    assert_empty(Dexpace.suppressed(error)) # swallowed, not attached: PAGE-32's own word
  end

  test "CALLER'S RESCUE, PAGE-15 (P7-105): a walk driven inside a rescue surfaces its close" do
    # `$!` is the caller's KeyError throughout the rescue arm. An ensure that read `$!` would
    # attach the close failure to it and swallow it; the recorded-primary shape surfaces it.
    body = fake_response_body(close_error: IOError.new("close"))
    surfaced = nil
    begin
      raise KeyError, "the caller's own, unrelated"
    rescue KeyError => error
      surfaced = assert_raises(IOError) do
        paginator_over([[1]], bodies: [body]).each_page { |_page| nil }
      end

      assert_empty(Dexpace.suppressed(error))
    end

    assert_equal("close", surfaced.message)
  end

  test "CALLER'S RESCUE, PAGE-15: the advance close surfaces from inside a caller's rescue too" do
    probes = [fake_response_body(close_error: IOError.new("advance")), fake_response_body]
    begin
      raise KeyError, "outer"
    rescue KeyError => error
      assert_raises(IOError) do
        paginator_over([[1], [2]], bodies: probes).each_page { |_page| nil }
      end
      assert_empty(Dexpace.suppressed(error))
    end
  end

  test "PAGE-15: with NOTHING in flight, a close error surfaces through a short-circuit terminal" do
    body = fake_response_body(close_error: IOError.new("close"))
    first_only = paginator_over([[1], [2]], bodies: [body, fake_response_body])

    assert_raises(IOError) { first_only.each_page { |page| break if page.items == [1] } }
    assert_raises(IOError) do
      paginator_over([[1], [2]], bodies: [fake_response_body(close_error: IOError.new("c")), nil])
        .pages.first
    end
  end

  test "P7-1: the surfaced close error is NOT wrapped: no Ruby terminal is unable to declare it" do
    # PAGE-15's middle clause ("re-thrown wrapped") is conditional on a terminal that cannot declare
    # the underlying I/O error type. Measured four ways on every CI row: Enumerable#first,
    # Lazy#first(2), an explicit break, and a plain block all deliver the close error unwrapped.
    # Vacuous antecedent, design §11.15's family. This test asserts the concrete class, so a wrapper
    # introduced later fails loudly rather than quietly changing what a caller must rescue.
    error = assert_raises(IOError) do
      paginator_over([[1]], bodies: [fake_response_body(close_error: IOError.new("close"))])
        .each_page { |_page| nil }
    end

    assert_instance_of(IOError, error)
    assert_nil(error.cause)
  end

  # The two-slot release, the frozen-primary caveat, a mid-walk parse failure, and the source scan.
  class ReleaseTest < DexpaceTestCase
    include PageFixtures

    test "PAGE-15: both held pages fail to close -> first primary, second suppressed" do
      # The ONLY reachable two-slot state: probe from INSIDE the loop, so page 2 is staged while
      # page 1 is still held, then break. `each`'s own ensure closes the walk, which releases both
      # -- so the assertion is on that raise, not on a later #close.
      first = fake_response_body(close_error: IOError.new("first"))
      second = fake_response_body(close_error: IOError.new("second"))
      view = paginator_over([[1], [2]], bodies: [first, second]).pages

      error = assert_raises(IOError) do
        view.each do |page|
          view.more?
          break if page.items == [1]
        end
      end

      assert_equal("first", error.message)
      assert_equal(["second"], Dexpace.suppressed(error).map(&:message))
      view.close # idempotent; no second release is attempted

      assert_equal([1, 1], [first.closes, second.closes])
    end

    test "the frozen-primary caveat is stated and observable, not worked around" do
      # Phase 4b's P4-13: attach_suppressed silently no-ops on a frozen primary. Asserting the
      # behaviour rather than pretending it does not exist.
      body = fake_response_body(close_error: IOError.new("close"))
      cause = KeyError.new("consumer").freeze

      error = assert_raises(KeyError) do
        paginator_over([[1]], bodies: [body]).each_page { |page| raise cause unless page.nil? }
      end

      assert_same(cause, error)
      assert_empty(Dexpace.suppressed(error))
      assert_equal(1, body.closes)
    end

    test "PAGE-13 / PAGE-15: a parse failure on page 2 releases held page 1 and stays primary" do
      probes = [fake_response_body(close_error: IOError.new("held")), fake_response_body]
      strategy = Class.new do
        define_method(:parse) do |response, template|
          raise KeyError, "parse" if response.request.url.query == "p=1"

          PageFixtures::ScriptedStrategy.new([[1], [2]]).parse(response, template)
        end
      end.new

      error = assert_raises(KeyError) do
        paginator_over([[1], [2]], bodies: probes, strategy: strategy).each_page { |_page| nil }
      end

      assert_equal("parse", error.message)
      assert_equal(["held"], Dexpace.suppressed(error).map(&:message))
      assert_equal([1, 1], probes.map(&:closes))
    end

    test "no `$!` and no bare `ensure` closes a page anywhere under lib/dexpace/page/" do
      root = File.expand_path("../../../lib/dexpace/page", __dir__)
      paths = Dir.glob("**/*.rb", base: root).map { |f| File.join(root, f) }
      paths << File.expand_path("../page.rb", root)
      code = paths.to_h { |path| [File.basename(path), uncommented(path)] }

      code.each_value { |text| refute_match(/\$!/, text) }
      with_ensure = code.select { |_name, text| text.include?("ensure") }.keys

      assert_equal(%w[items.rb pages.rb], with_ensure.sort)
      with_ensure.each { |name| assert_match(/rescue ::Exception => error/, code.fetch(name)) }
    end

    def uncommented(path)
      File.readlines(path).reject { |line| line.lstrip.start_with?("#") }.join
    end
  end
end
