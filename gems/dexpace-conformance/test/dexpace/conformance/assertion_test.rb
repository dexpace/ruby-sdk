# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# One conformance check as a value: the requirement IDs it exercises (what a waiver matches by --
# never the name), a human name and a callable body. Follows the phase-1 construction pattern
# (HTTP-3, HTTP-4, SEAM-29): `.new` private, a validating keyword `.build`, `Model.required!`'s one
# message form, the ids copied through `Model.own`, `#with` through `.build`.
class DexpaceConformanceAssertionTest < DexpaceTestCase
  Assertion = Dexpace::Conformance::Assertion

  test "is a frozen Data carrying its own ids, name and callable body" do
    ids = ["TRANSPORT-24"]
    assertion = Assertion.build(ids: ids, name: "maps every status totally", body: lambda { |_case|
    },)

    assert_equal(["TRANSPORT-24"], assertion.ids)
    assert_equal("maps every status totally", assertion.name)
    assert_predicate(assertion, :frozen?)
    assert_predicate(assertion.ids, :frozen?)
    refute_same(ids, assertion.ids, "the caller's array is copied, never aliased (Model.own)")
    assert_nil(assertion.call(:subject))
  end

  test "#call delegates to #body with the subject" do
    seen = nil
    assertion = Assertion.build(ids: ["X"], name: "records its subject",
                                body: ->(subject) { seen = subject },)

    assertion.call(:the_subject)

    assert_equal(:the_subject, seen)
  end

  test "HTTP-4 / SEAM-29: every member is required, named in the one message form" do
    %i[ids name body].each do |member|
      arguments = { ids: ["X"], name: "n", body: ->(_) {} }
      arguments[member] = nil
      error = assert_raises(Dexpace::InvalidArgumentError) { Assertion.build(**arguments) }

      assert_equal("#{member} is required", error.message)
    end
  end

  test "ids must be a non-empty collection of Strings and body must be callable" do
    body = ->(_) {}

    assert_raises(Dexpace::InvalidArgumentError) { Assertion.build(ids: [], name: "n", body: body) }
    assert_raises(Dexpace::InvalidArgumentError) { Assertion.build(ids: [:X], name: "n", body: body) }
    assert_raises(Dexpace::InvalidArgumentError) { Assertion.build(ids: ["X"], name: "n", body: :no) }
  end

  test "HTTP-2: the constructor is private, so .build is the one entry point" do
    assert_raises(NoMethodError) { Assertion.new(ids: ["X"], name: "n", body: ->(_) {}) }
  end

  test "#with derives through .build, re-validating on every interpreter" do
    assertion = Assertion.build(ids: ["X"], name: "n", body: ->(_) {})
    derived = assertion.with(name: "renamed")

    assert_equal("renamed", derived.name)
    assert_equal(["X"], derived.ids)
    assert_raises(Dexpace::InvalidArgumentError) { assertion.with(ids: nil) }
  end
end
