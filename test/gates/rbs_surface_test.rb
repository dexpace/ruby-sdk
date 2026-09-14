# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/rbs_surface"

# NFR-11: the core is concurrency-model agnostic and leaks no async-framework type into its
# public surface. This is the gate that would have caught Async::Task appearing there, and it is
# why the async pivot had to be core-owned (design §3.3).
class RbsSurfaceTest < GateCase
  # Laid out as a miniature workspace, gems/<gem>/sig/, so the task-level case can point the
  # gate at it through DEXPACE_GATE_ROOT.
  FIXTURES = File.join(ROOT, "test/fixtures/gates/rbs_surface")

  test "the real signatures reference nothing foreign" do
    assert_empty(RbsSurface.violations(Dir.glob(File.join(ROOT, "gems/*/sig/**/*.rbs"))))
  end

  test "rejects a signature referencing an async-framework type" do
    found = RbsSurface.violations([fixture("foreign.rbs")])

    assert_includes(found.join("\n"), "Async::Task")
  end

  test "rejects a foreign superclass, mixin, type alias and generic bound" do
    %w[superclass.rbs mixin.rbs type_alias.rbs generic_bound.rbs].each do |name|
      found = RbsSurface.violations([fixture(name)])

      assert_includes(found.join("\n"), "Async::Task", name)
    end
  end

  # `class Runner = Async::Task` publishes the async type under a Dexpace:: name -- NFR-11's
  # leak in its most direct form -- and a mixin's type argument is the same leak one token to
  # the right of its name.
  test "rejects a foreign class alias, module alias and mixin type argument" do
    %w[class_alias.rbs module_alias.rbs mixin_argument.rbs].each do |name|
      found = RbsSurface.violations([fixture(name)])

      assert_includes(found.join("\n"), "Async::", name)
    end
  end

  test "a comment mentioning a foreign type is not a leak" do
    assert_empty(RbsSurface.violations([fixture("comment_only.rbs")]))
  end

  # The normal RBS style is a relative reference resolved by nesting and a bare type variable,
  # and rbs validate accepts both; a scan that read names as written would refuse the first
  # real signature phase 1 writes.
  test "a type variable and a relative reference to a sibling Dexpace type are not leaks" do
    assert_empty(RbsSurface.violations([fixture("relative_and_generic.rbs")]))
  end

  test "rejects a foreign method-level generic bound, and not the parameter it bounds" do
    found = RbsSurface.violations([fixture("method_bound.rbs")]).join("\n")

    assert_includes(found, "Async::Task")
    refute_includes(found, "references T,")
  end

  test "rejects a foreign type inside every constructor a bare return type is not" do
    found = RbsSurface.violations([fixture("nested_positions.rbs")]).join("\n")

    assert_includes(found, "Async::Task")
    refute_includes(found, "references String")
  end

  test "a namespace that merely starts with Dexpace is foreign" do
    found = RbsSurface.violations([fixture("sibling_namespace.rbs")])

    assert_includes(found.join("\n"), "DexpaceX::Thing")
  end

  # The paths resolve together as one set, the way a consumer's steep check sees them, so a set
  # RBS itself cannot load is reported as a violation rather than raised past the gate.
  test "a set that cannot be resolved is a violation, not a pass" do
    found = RbsSurface.violations(Dir.glob(File.join(FIXTURES, "conflict/*.rbs")))

    assert_equal(1, found.length)
    assert_includes(found.first, "could not be resolved")
    assert_includes(found.first, "Dexpace::Twice")
  end

  test "the gate task fails on a fixture tree and passes on the repository" do
    _out, err, status = rake("gates:rbs_surface", "DEXPACE_GATE_ROOT" => FIXTURES)

    refute_predicate(status, :success?)
    assert_includes(err, "NFR-11")

    _out, err, status = rake("gates:rbs_surface")

    assert_predicate(status, :success?, err)
  end

  private

  def fixture(name)
    File.join(FIXTURES, "gems/fixture/sig", name)
  end
end
