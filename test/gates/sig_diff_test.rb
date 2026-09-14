# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/sig_diff"

# NFR-4. Design §9.1: a diff of sig/**/*.rbs against the previous release, failing when a public
# signature disappears **or narrows** without a major bump, with regeneration a deliberate act
# and never a way to silence an unintentional break.
class SigDiffTest < GateCase
  BASE_SIG = "module Dexpace\n  NAME: String\n  VERSION: String\nend\n"

  # A baseline with the two shapes a line-level comparison cannot see narrow: a method type
  # written across overload continuation lines, and a public method that a `private` line or a
  # `private def` could later hide without any declaration line changing.
  PARSER_SIG = <<~RBS
    module Dexpace
      class Parser
        def parse: (String raw) -> String
                 | (URI url) -> String
        def shown: () -> void
        private
        def hidden: () -> void
      end
    end
  RBS
  OVERLOAD = "             | (URI url) -> String\n"
  SHOWN = "    def shown: () -> void\n"
  HIDDEN = "    def hidden: () -> void\n"

  # PARSER_SIG rewritten so that one public declaration is gone, and the line the gate must name.
  NARROWED = {
    "a dropped overload on a continuation line" =>
      [PARSER_SIG.sub(OVERLOAD, ""), "def Dexpace::Parser#parse: (URI url) -> String"],
    "a public method moved under a private section" =>
      [PARSER_SIG.sub(SHOWN, "").sub(HIDDEN, HIDDEN + SHOWN), "def Dexpace::Parser#shown"],
    "a public method given the private modifier" =>
      [PARSER_SIG.sub(SHOWN, "    private def shown: () -> void\n"), "def Dexpace::Parser#shown"],
  }.freeze

  # PARSER_SIG rewritten so that nothing public is gone.
  UNCHANGED = {
    "an overload rewritten on one line" =>
      PARSER_SIG.sub("String\n#{OVERLOAD}", "String | (URI url) -> String\n"),
    "a private method removed" => PARSER_SIG.sub(HIDDEN, ""),
  }.freeze

  test "before the first release tag the gate says so and passes" do
    out, _err, status = rake("gates:sig_diff")

    assert_predicate(status, :success?)
    assert_includes(out, "no release tag yet")
  end

  test "the pre-release branch is reachable only with no v* tag at all" do
    assert_empty(
      `git -C #{ROOT} tag --list 'v*'`.split("\n"),
      "a v* tag exists, so the vacuous branch must no longer be taken",
    )
  end

  test "a removed signature fails against a tagged baseline" do
    assert_includes(violations_after("module Dexpace\nend\n"), "VERSION: String")
  end

  test "a narrowed signature fails, not just a removed one" do
    # Same declaration name, narrower type. A names-only comparison would call this unchanged.
    found = violations_after("module Dexpace\n  VERSION: \"0.0.0\"\nend\n")

    assert_includes(found, "VERSION: String")
  end

  test "a removed signature file fails" do
    in_tagged_fixture do |dir|
      FileUtils.rm(File.join(dir, "gems/dexpace-core/sig/dexpace/version.rbs"))

      assert_includes(SigDiff.violations(dir, "v0.0.0").join("\n"), "signature file removed")
    end
  end

  test "an unchanged tree is clean, and so is a reindented or reordered one" do
    in_tagged_fixture { |dir| assert_empty(SigDiff.violations(dir, "v0.0.0")) }
    assert_empty(violations_after("module Dexpace\n      VERSION: String\n  NAME: String\nend\n"))
  end

  test "a narrowing that leaves every declaration line in place still fails" do
    NARROWED.each do |label, (after, gone)|
      refute_equal(PARSER_SIG, after, label)
      assert_includes(violations_after(after, baseline: PARSER_SIG), gone, label)
    end
  end

  test "a rewrite that removes nothing public is not a break" do
    UNCHANGED.each do |label, after|
      refute_equal(PARSER_SIG, after, label)
      assert_empty(violations_after(after, baseline: PARSER_SIG), label)
    end
  end

  test "the gate task goes red against a tagged fixture" do
    in_tagged_fixture do |dir|
      write_sig(dir, "module Dexpace\nend\n")
      _out, err, status = rake("gates:sig_diff", "DEXPACE_GATE_ROOT" => dir)

      refute_predicate(status, :success?)
      assert_includes(err, "VERSION: String")
    end
  end

  private

  def violations_after(content, baseline: BASE_SIG)
    in_tagged_fixture(baseline) do |dir|
      write_sig(dir, content)
      SigDiff.violations(dir, "v0.0.0").join("\n")
    end
  end

  # A scratch repository whose v0.0.0 tag genuinely contains signatures. Cloning this repository
  # would not: nothing under gems/ has been committed here yet.
  def in_tagged_fixture(baseline = BASE_SIG)
    Dir.mktmpdir("dexpace-sig-diff") do |dir|
      FileUtils.mkdir_p(File.join(dir, "gems/dexpace-core/sig/dexpace"))
      File.write(File.join(dir, "gems/dexpace-core/sig/dexpace.rbs"), "module Dexpace\nend\n")
      write_sig(dir, baseline)
      [
        %w[init --quiet], %w[config user.email ci@example.invalid], %w[config user.name ci],
        %w[add -A], %w[commit --quiet -m sigs], %w[tag v0.0.0],
      ].each { |command| system("git", "-C", dir, *command, exception: true) }

      yield dir
    end
  end

  def write_sig(dir, content)
    File.write(File.join(dir, "gems/dexpace-core/sig/dexpace/version.rbs"), content)
  end
end
