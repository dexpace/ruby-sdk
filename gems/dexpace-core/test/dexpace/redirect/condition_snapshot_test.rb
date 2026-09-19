# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/recovery_fixtures"

# Exercises: REDIR-20, REDIR-16 (the visited set's shape), HTTP-3, HTTP-4, SEAM-29 -- the
# read-only, defensively-copied snapshot a redirect predicate receives, as a phase-1 Data:
# validating .build, private .new, the collection copied and frozen at construction, #with
# through .build on every interpreter (Data#with skips initialize on the 3.2 floor).
class DexpaceRedirectConditionSnapshotTest < DexpaceTestCase
  include RecoveryFixtures

  Snapshot = Dexpace::Redirect::ConditionSnapshot

  def snapshot(redirect_count: 1, visited: Set["https://a.example/x"])
    Snapshot.build(response: build_response(302), redirect_count: redirect_count,
                   visited_uris: visited,)
  end

  test "REDIR-20: exposes the response, the count and the visited set" do
    response = build_response(302)
    snap = Snapshot.build(response: response, redirect_count: 2,
                          visited_uris: Set["https://a.example/x", "https://a.example/y"],)

    assert_same(response, snap.response)
    assert_equal(2, snap.redirect_count)
    assert_equal(Set["https://a.example/x", "https://a.example/y"], snap.visited_uris)
    assert_predicate(snap, :frozen?)
  end

  test "REDIR-20: visited_uris is a frozen copy, never the caller's Set" do
    live = Set["https://a.example/x"]
    snap = snapshot(visited: live)

    refute_same(live, snap.visited_uris)
    assert_predicate(snap.visited_uris, :frozen?)
    live << "https://b.example/z"

    refute_includes(snap.visited_uris, "https://b.example/z") # the later write never reaches it
    assert_raises(FrozenError) { snap.visited_uris << "https://c.example/" }
  end

  test "REDIR-20: the copy is deep -- a String the caller still holds cannot reach the set" do
    entry = +"https://a.example/x"
    snap = snapshot(visited: [entry])
    entry << "?tampered"

    assert_equal(Set["https://a.example/x"], snap.visited_uris)
    assert(snap.visited_uris.all?(&:frozen?))
  end

  test "REDIR-20: insertion order is kept (verified fact 4)" do
    snap = snapshot(visited: %w[https://c.example/ https://a.example/ https://b.example/])

    assert_equal(%w[https://c.example/ https://a.example/ https://b.example/],
                 snap.visited_uris.to_a,)
  end

  test "HTTP-4 / SEAM-29: a missing member is named in the one message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Snapshot.build(response: nil, redirect_count: 0, visited_uris: Set.new)
    end

    assert_equal("response is required", error.message)
    assert_equal("redirect_count is required",
                 assert_raises(Dexpace::InvalidArgumentError) do
                   Snapshot.build(response: build_response(302), redirect_count: nil,
                                  visited_uris: Set.new,)
                 end.message,)
    assert_equal("visited_uris is required",
                 assert_raises(Dexpace::InvalidArgumentError) do
                   Snapshot.build(response: build_response(302), redirect_count: 0,
                                  visited_uris: nil,)
                 end.message,)
  end

  test "a non-Response, a negative count and a non-Integer count are refused" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Snapshot.build(response: "302", redirect_count: 0, visited_uris: Set.new)
    end
    assert_raises(Dexpace::InvalidArgumentError) { snapshot(redirect_count: -1) }
    assert_raises(Dexpace::InvalidArgumentError) { snapshot(redirect_count: 1.5) }
  end

  test "the generated constructor is private" do
    assert_raises(NoMethodError) do
      Snapshot.new(response: build_response(302), redirect_count: 0, visited_uris: Set.new)
    end
  end

  test "HTTP-3: #with derives through .build, so validation runs on every interpreter" do
    snap = snapshot(redirect_count: 1)
    derived = snap.with(redirect_count: 2)

    assert_equal(2, derived.redirect_count)
    assert_equal(1, snap.redirect_count)
    assert_raises(Dexpace::InvalidArgumentError) { snap.with(redirect_count: -1) }
    assert_raises(Dexpace::InvalidArgumentError) { snap.with(response: nil) }
  end
end
