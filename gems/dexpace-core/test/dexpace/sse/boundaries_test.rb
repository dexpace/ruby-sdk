# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/sse_fixtures"

# Exercises: SSE-37 (no built-in done-sentinel, no error-envelope recognition -- the two halves
# the require-and-constant audit cannot scan for, since a sentinel is a string literal and no
# scanner tells "[DONE]" from any other string), SSE-38 (no auto-reconnect, no persisted
# last-event-id, no reconnect header), SSE-16 as SSE-38 cites it. Design section 7.2: these are
# "satisfied by omission AND asserted by test, since the temptation to add them is real". That is
# why this file exists rather than a comment; the mechanical half of SSE-37 is
# `gates:serde_boundary` (test/gates/serde_boundary_test.rb). No lib/ mirror: it asserts
# absences across the subsystem.
class DexpaceSSEBoundariesTest < DexpaceTestCase
  include SSEFixtures

  SSE_FILES = Dir.glob(File.expand_path("../../../lib/dexpace/sse{,/**/*}.rb", __dir__)).freeze

  test "SSE-37: [DONE] is an ordinary data value and does not terminate the stream" do
    stream, = stream_over("data: [DONE]\n\ndata: after\n\n")

    assert_equal([["[DONE]"], ["after"]], stream.events.to_a.map(&:data))
  end

  test "SSE-37: the other conventional sentinels are ordinary data values too" do
    bytes = "data: DONE\n\nevent: done\ndata: x\n\ndata: {\"done\":true}\n\ndata: end\n\n"
    stream, = stream_over(bytes)

    assert_equal(4, stream.events.to_a.size)
  end

  test "SSE-37: an event named 'error' is an ordinary event and raises nothing" do
    stream, = stream_over("event: error\ndata: {\"message\":\"x\"}\n\ndata: after\n\n")
    events = stream.events.to_a

    assert_equal(2, events.size)
    assert_equal("error", events.first.event)
    assert_equal(["{\"message\":\"x\"}"], events.first.data)
  end

  test "SSE-37: an error-shaped payload is handed to the mapper like any other, undecoded" do
    seen = []
    stream, = stream_over("event: error\ndata: {\"error\":{\"code\":1}}\n\n")
    stream.typed { |name, data| seen << [name, data] }.each { |_v| nil }

    assert_equal([["error", "{\"error\":{\"code\":1}}"]], seen)
  end

  test "SSE-37: no core SSE constant's ancestry or constant table reaches a serde namespace" do
    # The runtime companion of the parsed scan: the SSE namespace defines nothing whose
    # ancestors or nested constants name Serde or JSON.
    checked = 0
    Dexpace::SSE.constants(false).each do |name|
      value = Dexpace::SSE.const_get(name)
      next unless value.is_a?(::Module)

      checked += 1

      # Object's own ancestors are excluded: another gem's suite in the same test:gems process
      # loads the json gem, which mixes JSON::GeneratorMethods into Object itself.
      refute_match(/Serde|JSON/, (value.ancestors - ::Object.ancestors).join(","), name)
      refute_match(/Serde|JSON/, value.constants(false).join(","), name)
    end

    assert_equal(8, checked, "the eight SSE modules and classes were all checked")
  end

  test "SSE-37: no SSE source file requires a serialization feature or names a serde constant" do
    # The gate's own scan is parsed (tools/serde_boundary.rb); this is the coarse text check that
    # would catch a `require "json"` or a `Dexpace::Serde` reference before the gate runs. It
    # scans code lines only -- the YARD on lib/dexpace/sse.rb is REQUIRED to say the words.
    refute_empty(SSE_FILES)
    SSE_FILES.each do |path|
      code = File.readlines(path).reject { |line| line.lstrip.start_with?("#") }.join

      refute_match(%r{require\s*\(?\s*["'](?:json|dexpace/serde)}, code, path)
      refute_match(/\bDexpace::Serde\b|\bJSON\b/, code, path)
    end
  end

  test "SSE-38: the subsystem constructs no request and holds no transport" do
    # A reconnect would need one of the two. Neither exists, and this asserts the absence rather
    # than describing it -- over every method of every SSE class, private ones included.
    [Dexpace::SSE::Stream, Dexpace::SSE::TypedStream, Dexpace::SSE::Reader,
     Dexpace::SSE::LineReader,].each do |klass|
      names = (klass.instance_methods + klass.private_instance_methods(false)).map(&:to_s)

      refute(names.any? { |m| m.match?(/reconnect|request|transport|last_event_id/) }, klass.name)
    end
    code = SSE_FILES.flat_map { |path| File.readlines(path) }
      .reject { |line| line.lstrip.start_with?("#") }.join

    refute_match(/Last-Event-ID|Dexpace::Request\b|Transport|reconnect/i, code)
  end

  test "SSE-38/SSE-16: a second event's id is absent, so no last-event-id is persisted" do
    stream, = stream_over("id: 1\ndata: a\n\ndata: b\n\n")

    assert_nil(stream.events.to_a.last.id)
  end

  test "SSE-38: the retry hint is surfaced and never acted on" do
    stream, = stream_over("retry: 5\ndata: a\n\ndata: b\n\n")
    events = stream.events.to_a

    assert_equal([5, nil], events.map(&:retry))
  end

  test "SSE-38: an exhausted stream stays exhausted and does not reopen" do
    stream, resource = stream_over("data: a\n\n")

    assert_equal(1, stream.events.to_a.size)
    assert_predicate(stream, :closed?)
    assert_equal(1, resource.closes)
    assert_raises(Dexpace::SSE::StreamStateError) { stream.events }
  end

  test "SSE-38: a callback listener contract is not offered -- the MAY is not taken" do
    refute_respond_to(Dexpace::SSE::Stream, :listen)
    own = Dexpace::SSE::Stream.instance_methods(false) + Dexpace::SSE::Stream.singleton_methods(false)

    assert_equal(%i[each events typed open owning borrowing].sort, own.sort)
  end
end
