# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/surface"

# NFR-4, the half RBS cannot see. Design §9.1: "RBS describes what someone wrote, not what Ruby
# defines" -- Data.define's generated readers, define_method, method_missing and a require-time
# register call are all invisible to a signature file.
class SurfaceSnapshotTest < GateCase
  # An in-process stand-in for a gem namespace, holding the one construction the walker must
  # see through: design §4's `class X < Data.define(...)`, whose readers Ruby defines on the
  # anonymous superclass and not on X itself.
  module Fixture
    class Sample < Data.define(:code, :name)
      def extra = nil
    end

    # Design §4's two-parallel-hashes model hides its members: the readers stay public on the
    # anonymous superclass and are private on the model, and the surface is the model's.
    class Hidden < Data.define(:values, :casing)
      private :values, :casing

      def names = casing.values
    end

    module Plain
      def self.build = nil
    end

    LIMIT = 3
  end

  # Each adapter's manifest and the namespace it shares with its siblings, which is where its
  # manifest begins: an adapter's lines are what it adds to the tree, and core's own `Dexpace`
  # line is core's.
  SHARED_NAMESPACES = {
    "dexpace-transport-net_http" => "Dexpace::Transport",
    "dexpace-transport-async_http" => "Dexpace::Transport",
    "dexpace-serde-json" => "Dexpace::Serde",
    "dexpace-async-thread" => "Dexpace::Async",
  }.freeze

  test "the committed manifests match the runtime tree" do
    _out, err, status = rake("gates:surface_snapshot")

    assert_predicate(status, :success?, err)
  end

  test "an unrecorded constant fails the gate" do
    _out, err, status = rake("gates:surface_snapshot", "DEXPACE_SURFACE_EXTRA" => "Injected")

    refute_predicate(status, :success?)
    assert_includes(err, "Injected")
  end

  # The walk starts at Dexpace, not at the gem's own constant: an entry file can define beside
  # its namespace as easily as inside it, and only the root sees both. The qualified injection
  # lands in each subprocess that defines its owner -- the two transports -- and the drift is
  # reported for those two gems, as a line the walk found and not as a load failure.
  test "a constant placed beside an adapter's namespace fails the gate" do
    _out, err, status = rake(
      "gates:surface_snapshot", "DEXPACE_SURFACE_EXTRA" => "Dexpace::Transport::Shared",
    )

    refute_predicate(status, :success?)
    assert_includes(err, "  + Dexpace::Transport::Shared : Integer")
    assert_includes(err, "dexpace-transport-net_http: runtime surface differs")
    assert_includes(err, "dexpace-transport-async_http: runtime surface differs")
    refute_includes(err, "would not load")
  end

  test "each adapter's committed manifest starts at the namespace it shares, not its own" do
    SHARED_NAMESPACES.each do |name, namespace|
      lines = File.readlines(File.join(ROOT, "test/fixtures/surface/#{name}.txt"), chomp: true)

      assert_equal(namespace, lines.first, name)
      refute_includes(lines, "Dexpace", "#{name}: core's own line belongs to core's manifest")
    end
  end

  test "the message says both artifacts must be regenerated" do
    _out, err, _status = rake("gates:surface_snapshot", "DEXPACE_SURFACE_EXTRA" => "Injected")

    assert_includes(err, "sig/")
    assert_includes(err, "surface:regenerate")
  end

  test "Data.define's generated readers appear in the manifest, which RBS cannot see" do
    lines = Surface.manifest("SurfaceSnapshotTest::Fixture").lines.map(&:chomp)

    assert_includes(lines, "SurfaceSnapshotTest::Fixture::Sample#code")
    assert_includes(lines, "SurfaceSnapshotTest::Fixture::Sample#name")
    assert_includes(lines, "SurfaceSnapshotTest::Fixture::Sample#extra")
    assert_includes(lines, "SurfaceSnapshotTest::Fixture::LIMIT : Integer")
    assert_includes(lines, "SurfaceSnapshotTest::Fixture::Plain.build")
    refute_includes(
      lines, "SurfaceSnapshotTest::Fixture::Sample#with",
      "Data's own #with is Ruby's surface, not this repository's",
    )
  end

  test "a generated reader the model makes private is not in the manifest" do
    lines = Surface.manifest("SurfaceSnapshotTest::Fixture").lines.map(&:chomp)

    assert_includes(lines, "SurfaceSnapshotTest::Fixture::Hidden#names")
    refute_includes(lines, "SurfaceSnapshotTest::Fixture::Hidden#values")
    refute_includes(lines, "SurfaceSnapshotTest::Fixture::Hidden#casing")
  end

  # An adapter's manifest is what its entry file adds, and nothing the tree already held: with
  # one line per method the subtraction is exact even when the addition is a method on a module
  # that already had some.
  test "a contribution holds only the lines the block added" do
    added = Surface.contribution("SurfaceSnapshotTest::Fixture") do
      Fixture::Plain.define_singleton_method(:later) { nil }
      Fixture.const_set(:Later, Module.new)
    end

    assert_equal(
      "SurfaceSnapshotTest::Fixture::Later\nSurfaceSnapshotTest::Fixture::Plain.later\n", added,
    )
  ensure
    Fixture.send(:remove_const, :Later) if Fixture.const_defined?(:Later, false)
    if Fixture::Plain.respond_to?(:later)
      Fixture::Plain.singleton_class.send(:remove_method, :later)
    end
  end

  # Core's own case: nothing is defined before its entry file loads, so its manifest is the
  # whole tree.
  test "a contribution to a root that does not exist yet is the whole tree" do
    added = Surface.contribution("SurfaceSnapshotTest::Fresh") do
      SurfaceSnapshotTest.const_set(:Fresh, Module.new { def self.build = nil })
    end

    assert_equal("SurfaceSnapshotTest::Fresh\nSurfaceSnapshotTest::Fresh.build\n", added)
  ensure
    if SurfaceSnapshotTest.const_defined?(:Fresh, false)
      SurfaceSnapshotTest.send(:remove_const, :Fresh)
    end
  end
end
