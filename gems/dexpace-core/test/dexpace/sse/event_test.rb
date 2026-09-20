# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "pp"
require_relative "../../test_helper"
require_relative "../../../lib/dexpace/sse/event"

# Exercises: SSE-20 (immutable, defensively-copied read-only data list, copied again on
# copy-with-changes), SSE-21 (structural equality and hash over all five fields, a stable string
# form), SSE-22 (the is-empty predicate, true only when all five are unset), SSE-4 and SSE-6 as
# they bear on the predicate; HTTP-4/SEAM-29's construction pattern. Split under
# Metrics/ClassLength: the immutable value, then the predicate and the construction pattern.
class DexpaceSSEEventTest < DexpaceTestCase
  # SSE-20 and SSE-21: the immutable, defensively-copied value.
  class ValueTest < DexpaceTestCase
    Event = Dexpace::SSE::Event

    test "SSE-20: mutating the list the event was built from cannot reach inside it" do
      # `+` on each literal because this file is frozen_string_literal: true, under which
      # `original[0] << "!"` raises FrozenError and the test would error rather than assert.
      original = [+"a", +"b"]
      event = Event.build(data: original)
      original << "c"
      original[0] << "!"

      assert_equal(%w[a b], event.data)
    end

    test "SSE-20: the data list and its elements are frozen" do
      event = Event.build(data: [+"a"])

      assert_predicate(event.data, :frozen?)
      assert_predicate(event.data.first, :frozen?)
      assert_raises(::FrozenError) { event.data << "b" }
    end

    test "SSE-20: #with copies the data list rather than sharing it" do
      # verified fact 5: raw Data#with SHARES its members. Dexpace::Model#with routes through
      # .build and Model.own -- which hands an ALREADY deep-frozen list back as it is
      # (make_shareable copies only what is not yet shareable), so the observable clause is that
      # nothing mutable is ever shared. What Data#with alone would lose on the 3.2 floor, where it
      # skips #initialize, is the VALIDATION on derivation, asserted last.
      source = [+"a"]
      event = Event.build(data: source)
      derived = event.with(id: "1")

      refute_same(source, derived.data)
      assert_equal(["a"], derived.data)
      assert_equal("1", derived.id)
      assert_predicate(derived.data, :frozen?)
      source[0] << "!"

      assert_equal(["a"], derived.data)
      assert_raises(Dexpace::InvalidArgumentError) { event.with(retry: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { event.with(data: "not a list") }
    end

    test "SSE-20: the same frozen reference comes back from every accessor call" do
      event = Event.build(data: ["a"])

      assert_same(event.data, event.data)
    end

    test "SSE-20: the scalar fields are frozen copies, never the caller's live Strings" do
      id = +"live"
      event = Event.build(id: id, event: +"e", comment: +"c")
      id << "!"

      assert_equal("live", event.id)
      assert_predicate(event.id, :frozen?)
      assert_predicate(event.event, :frozen?)
      assert_predicate(event.comment, :frozen?)
    end

    test "SSE-21: equality and hash are over all five fields" do
      a = Event.build(id: "1", event: "e", data: ["d"], comment: "c", retry: 5)
      b = Event.build(id: "1", event: "e", data: ["d"], comment: "c", retry: 5)

      assert_equal(a, b)
      assert_equal(a.hash, b.hash)
      assert(a.eql?(b))
      refute_equal(a, b.with(retry: 6))
      refute_equal(a, b.with(comment: "other"))
      refute_equal(a, b.with(data: %w[d e]))
      refute_equal(a, b.with(id: nil))
      refute_equal(a, b.with(event: nil))
    end

    test "SSE-21: the string form is stable and names the type" do
      event = Event.build(data: ["d"])

      assert_match(/Dexpace::SSE::Event/, event.inspect)
      assert_equal(event.inspect, Event.build(data: ["d"]).inspect)
      assert_equal(event.inspect, event.to_s)
      assert_match(/Dexpace::SSE::Event/, event.pretty_inspect)
    end
  end

  # SSE-22 and the construction pattern.
  class PredicateTest < DexpaceTestCase
    Event = Dexpace::SSE::Event

    test "SSE-22: #empty? is true only when all five fields are unset" do
      assert_predicate(Event.build, :empty?)
      refute_predicate(Event.build(id: "1"), :empty?)
      refute_predicate(Event.build(event: "e"), :empty?)
      refute_predicate(Event.build(data: ["x"]), :empty?)
      refute_predicate(Event.build(comment: "c"), :empty?)
      refute_predicate(Event.build(retry: 0), :empty?)
    end

    test "SSE-22/SSE-6: a comment-only keep-alive reports non-empty: a comment is content" do
      refute_predicate(Event.build(comment: "keep-alive"), :empty?)
    end

    test "SSE-22/SSE-4: a present-but-empty field is not 'unset'" do
      # SSE-4 makes present-but-empty distinct from absent, so neither of these is empty.
      refute_predicate(Event.build(event: ""), :empty?)
      refute_predicate(Event.build(data: [""]), :empty?)
      refute_predicate(Event.build(id: ""), :empty?)
    end

    test "an event is frozen at construction and cannot be built through .new or .[]" do
      assert_predicate(Event.build, :frozen?)
      assert_raises(::NoMethodError) { Event.new(id: nil) }
      assert_raises(::NoMethodError) { Event[nil, nil, [], nil, nil] }
    end

    test "SSE-20: non-ASCII data survives construction with its encoding intact" do
      event = Event.build(data: ["café"])

      assert_equal("café", event.data.first)
      assert_equal(::Encoding::UTF_8, event.data.first.encoding)
    end

    test "HTTP-4: the members are validated by name, in the order the wire lists them" do
      assert_raises(Dexpace::InvalidArgumentError) { Event.build(data: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { Event.build(data: "not a list") }
      assert_raises(Dexpace::InvalidArgumentError) { Event.build(data: [1]) }
      assert_raises(Dexpace::InvalidArgumentError) { Event.build(id: 1) }
      assert_raises(Dexpace::InvalidArgumentError) { Event.build(event: :e) }
      assert_raises(Dexpace::InvalidArgumentError) { Event.build(comment: 1) }
      assert_raises(Dexpace::InvalidArgumentError) { Event.build(retry: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { Event.build(retry: 1.5) }
      assert_raises(Dexpace::InvalidArgumentError) { Event.build(retry: "5") }
    end

    test "the five members are the five tracked fields, retry included and so named" do
      assert_equal(%i[id event data comment retry], Event.members)
      assert_equal(5, Event.build(retry: 5).retry)
      assert_equal({ id: nil, event: nil, data: [], comment: nil, retry: nil }, Event.build.to_h)
    end
  end
end
