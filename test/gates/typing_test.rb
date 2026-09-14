# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# NFR-3, and docs/knowledge/notes/type-system.md: RBS under sig/, gated by rbs validate and
# steep check, no Sorbet anywhere. Adoption is target-by-target so a relaxation is a named
# target rather than a blanket ignore.
class TypingTest < GateCase
  STEEPFILE = File.read(File.join(ROOT, "Steepfile"))

  test "names one Steep target per gem, from day one" do
    %w[core net_http async_http serde_json async_thread conformance].each do |name|
      assert_includes(STEEPFILE, "target :#{name}")
    end
  end

  test "core is configured strict" do
    assert_match(/target :core do.*D::Ruby\.strict/m, STEEPFILE)
  end

  test "no file in the repository carries a Sorbet sigil" do
    # A sigil is a magic comment at column 0; a mention inside prose is not one.
    offenders = Dir.glob(File.join(ROOT, "{gems,test,tasks,tools,.rubocop}/**/*.rb"))
      .select { |file| File.foreach(file).any? { |line| line.start_with?("# typed:") } }

    assert_empty(offenders)
  end

  test "rbs validate and steep check both pass" do
    %w[rbs:validate steep].each do |task|
      _out, err, status = rake(task)

      assert_predicate(status, :success?, "#{task}: #{err}")
    end
  end

  test "rbs validate rejects a malformed signature" do
    Dir.mktmpdir("dexpace-rbs-fixture") do |dir|
      File.write(File.join(dir, "broken.rbs"), "module Dexpace\n  VERSION: Nonexistent::Type\nend\n")
      _out, err, status = Open3.capture3(
        "bundle", "exec", "rbs", "-I", dir, "--no-collection", "validate", chdir: ROOT,
      )

      refute_predicate(status, :success?)
      assert_includes(err, "Nonexistent")
    end
  end

  test "the rbs collection lock and the Gemfile lock are ignored, never tracked" do
    # Both exist on disk after a resolve; "not committed" means not tracked by git.
    tracked = `git -C #{ROOT} ls-files rbs_collection.lock.yaml Gemfile.lock`.strip

    assert_empty(tracked)
    assert_includes(File.read(File.join(ROOT, ".gitignore")), "/rbs_collection.lock.yaml")
    assert_includes(File.read(File.join(ROOT, ".gitignore")), "/Gemfile.lock")
  end
end
