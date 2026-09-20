# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"
require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/page_fixtures"

# Exercises: PAGE-13, PAGE-15, PAGE-19, PAGE-21, PAGE-22, PAGE-23, PAGE-24, PAGE-31 (the Ruby facts
# they rest on) -- the phase-7c design's eight verified facts plus the ones the cross-check and the
# build found, re-run as a standing test on every CI row rather than once in a scratch script
# (5a's, 5b's, 5c's, 6a's, 6b's and 6c's precedent). Run on 3.2.11, 3.3.12, 3.4.10 and 4.0.6 on
# 2026-09-20: every fact holds identically on every row, uri 0.12.5 / 0.13.3 / 1.0.4 / 1.1.1
# included. 6b's redirect/matrix_facts_test.rb already pins the join facts (a query-only reference
# preserves the path; join(base, "") answers the base; join(base, nil) raises ArgumentError; join
# raises on a space and on nothing else -- mailto:, javascript:, http:foo all RESOLVE); they are
# cited, not re-asserted. No lib/ mirror: it asserts the interpreter, not a file.
class DexpacePageMatrixFactsTest < DexpaceTestCase
  include PageFixtures

  PARSER = ::URI::RFC3986_PARSER

  # A scoped resource whose close raises, driven the four ways PAGE-15's clause could be reached.
  class Scoped
    include Enumerable

    def each
      yield 1
      yield 2
      yield 3
    ensure
      raise IOError, "close"
    end
  end

  test "fact 1 (R8, P7-1): a close error from an ensure reaches the caller UNWRAPPED, four ways" do
    assert_instance_of(IOError, assert_raises(IOError) { Scoped.new.first })
    assert_instance_of(IOError, assert_raises(IOError) { Scoped.new.lazy.map { |x| x }.first(2) })
    assert_instance_of(IOError, assert_raises(IOError) { Scoped.new.each { |x| break x if x > 1 } })
    assert_instance_of(IOError, assert_raises(IOError) { Scoped.new.each { |_x| :v } })
  end

  test "fact 1 (R8): a raising ensure REPLACES an in-flight consumer error as the primary" do
    error = assert_raises(IOError) { Scoped.new.each { |x| raise ArgumentError, "consumer" if x } }

    assert_instance_of(ArgumentError, error.cause) # nothing lost; the ORDER is PAGE-13's inverse
  end

  test "fact 2 (P7-105): $! is the CALLER's inside a method called from the caller's rescue" do
    reader = -> { $! } # rubocop:disable Style/SpecialGlobalVars -- the bare global IS the fact
    begin
      raise KeyError, "caller"
    rescue KeyError
      assert_instance_of(KeyError, reader.call)
    end

    assert_nil(reader.call)
  end

  test "fact 3 (PAGE-31): a re-arm loop over inline-settled futures is flat; recursion is not" do
    # The recursive shape overflows at ~2,600 pages through the real Completer on every row
    # (measured); asserting the overflow itself would take seconds per row, so the standing test
    # asserts the flat loop over 20,000 and async_paginator_test.rb the engine's own depth.
    count = 0
    rearm = true
    while rearm
      rearm = false
      completer = Dexpace::Async::Completer.new
      completer.fulfil(1)
      completer.future.on_settle do
        count += 1
        rearm = count < 20_000
      end
    end

    assert_equal(20_000, count)
  end

  test "fact 5 (PAGE-22): Ruby's www-form helpers are the exact inverse of RFC 3986 coding" do
    assert_equal([["q", "a b"]], ::URI.decode_www_form("q=a+b"))
    assert_equal("a+b", ::URI.encode_www_form_component("a b"))
    assert_equal("a%20b%2A~%2B%2F%21%28%29%27",
                 Dexpace::PercentEncoding.encode_component("a b*~+/!()'"),)
    assert_equal("a+b", Dexpace::PercentEncoding.decode_component("a+b"))
  end

  test "fact 6 (PAGE-19, P7-104): join resolves what this client cannot dispatch, successfully" do
    base = "https://api.example.com/repo/issues?page=1"
    resolved = { "mailto:a@b" => ["mailto", nil], "javascript:alert(1)" => ["javascript", nil],
                 "http:foo" => ["http", nil], "http:///p" => ["http", ""], }

    resolved.each do |reference, (scheme, host)|
      target = PARSER.join(base, reference)

      assert_equal([scheme, host], [target.scheme, target.host], reference)
    end
  end

  test "fact 7 (P7-4): query = nil removes the query; query = \"\" leaves a dangling ?" do
    removed = PARSER.parse("https://x/a?page=1")
    removed.query = nil
    dangling = PARSER.parse("https://x/a?page=1")
    dangling.query = ""

    assert_equal(["https://x/a", "https://x/a?"], [removed.to_s, dangling.to_s])
    assert_predicate(Float::INFINITY, :positive?)
    assert_operator(3, :<, Float::INFINITY)
  end

  # The splice facts (PAGE-21, PAGE-24), the fiber-storage facts, and the cross-check's.
  class SpliceAndFiberTest < DexpaceTestCase
    include PageFixtures

    PARSER = ::URI::RFC3986_PARSER

    test "fact 4 (PAGE-21, PAGE-24): query= round-trips every parser-produced query via Request" do
      disagreements = []
      (0x20..0x7e).each do |byte|
        char = byte.chr
        next if char == "%" # a bare % is not a pct-encoding and does not parse: not a splice input

        produced = PARSER.parse("https://h/p?k=#{char}&x=1").query
        copy = PARSER.parse("https://h/p?k=#{char}&x=1").dup
        copy.query = produced
        disagreements << char unless fake_request(url: copy).url.query == produced
      end

      assert_empty(disagreements)
      full = Dexpace::URL.parse!("https://user:pw@h:8443/a/b?flag&filter=a:b&page=2#frag")
      copy = full.dup
      query = copy.query
      copy.query = query

      assert_equal("https://user:pw@h:8443/a/b?flag&filter=a:b&page=2#frag",
                   Dexpace::URL.external_form(fake_request(url: copy).url),)
    end

    test "fact 4: the canonicalising happens at PARSE time, on exactly seven bytes" do
      canonicalised = (0x20..0x7e).map(&:chr).reject do |char|
        PARSER.parse("https://h/p?k=#{char}").query == "k=#{char}"
      rescue ::URI::InvalidURIError
        false
      end

      assert_equal([" ", '"', "#", "'", "<", ">", "`"], canonicalised - ["%"])
    end

    test "fact 8: Fiber[] is visible inside an Enumerator's fiber, created at the FIRST pull" do
      Fiber[:dexpace_page_probe] = :before
      ::Thread.current[:dexpace_page_local] = :before
      enumerator = Enumerator.new do |y|
        loop { y << [Fiber[:dexpace_page_probe], ::Thread.current[:dexpace_page_local]] }
      end
      Fiber[:dexpace_page_probe] = :after_new
      first = enumerator.next
      Fiber[:dexpace_page_probe] = :after_first_pull
      second = enumerator.next

      assert_equal([[:after_new, nil], [:after_new, nil]], [first, second])
    ensure
      Fiber[:dexpace_page_probe] = nil
      ::Thread.current[:dexpace_page_local] = nil
    end

    test "fact 8 (applied): a correlation value set before a view is first driven IS seen" do
      seen = []
      strategy = Class.new do
        define_method(:parse) do |_response, _template|
          seen << Fiber[:dexpace_page_correlation]
          Dexpace::Page::Info.terminal(items: [1])
        end
      end.new
      Fiber[:dexpace_page_correlation] = :set_before
      enumerator = paginator_over([[1]], strategy: strategy).items.to_enum(:each)
      Fiber[:dexpace_page_correlation] = :set_after_construction
      enumerator.next

      assert_equal([:set_after_construction], seen)
    ensure
      Fiber[:dexpace_page_correlation] = nil
    end

    test "cross-check facts: Model.own deep-copies and freezes elements; a Data holds no ivars" do
      element = Object.new
      owned = Dexpace::Model.own([element])

      refute_same(element, owned.first)
      assert_predicate(owned.first, :frozen?)
      assert_raises(TypeError) { Dexpace::Model.own([proc {}]) }
      assert_empty(Data.define(:a).new(a: 1).instance_variables)
    end

    test "cross-check facts: fulfil after cancel closes the response; a nil token dies in retry" do
      closes = 0
      resource = Object.new
      resource.define_singleton_method(:close) { closes += 1 }
      completer = Dexpace::Async::Completer.new
      completer.future.cancel(:test)

      refute(completer.fulfil(resource))
      assert_equal(1, closes)

      pipeline = Dexpace::Pipeline.standard(->(_r, _o, _c) { raise "unreached" })
      assert_raises(NoMethodError) do
        pipeline.call(fake_request, Dexpace::RequestOptions::EMPTY, nil)
      end
    end
  end
end
