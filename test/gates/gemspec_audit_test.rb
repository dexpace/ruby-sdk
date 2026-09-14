# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/gemspec_audit"

# SEAM-1 / NFR-1 / NFR-2. Design §2.4: "that test IS the SEAM-1 dependency audit; there is no
# scope declaration to lean on instead."
class GemspecAuditTest < GateCase
  FIXTURES = File.join(ROOT, "test/fixtures/gates/gemspec_audit")

  test "the real repository is clean" do
    assert_empty(GemspecAudit.violations(ROOT))
  end

  test "rejects a core gemspec with any runtime dependency" do
    found = GemspecAudit.violations(File.join(FIXTURES, "extra_core_dependency"))

    assert_includes(found.join("\n"), "dexpace-core declares 1 runtime dependency")
  end

  test "rejects an adapter with two third-party dependencies" do
    found = GemspecAudit.violations(File.join(FIXTURES, "two_third_party"))

    assert_includes(found.join("\n"), "NFR-2 allows core plus at most one")
  end

  test "rejects an adapter whose core constraint disagrees with VERSIONS" do
    found = GemspecAudit.violations(File.join(FIXTURES, "stale_constraint"))

    assert_includes(found.join("\n"), "expected ~> 0.0")
  end

  test "rejects a gemspec whose Ruby floor is not the declared one" do
    found = GemspecAudit.violations(File.join(FIXTURES, "wrong_floor"))

    assert_includes(found.join("\n"), "expected >= 3.2 (NFR-10)")
  end

  # NFR-12's ordering half, which the design lists among the audit's assertions. RubyGems sorts
  # spec.files in its own reader, so the unsorted fixture is the positive control: what the audit
  # refuses is the list that depends on git.
  test "rejects a gemspec whose file list comes from a subprocess" do
    listed = GemspecAudit.violations(File.join(FIXTURES, "git_listed_files"))

    assert_includes(listed.join("\n"), "the gemspec runs a subprocess")
    assert_empty(GemspecAudit.violations(File.join(FIXTURES, "unsorted_files")))
  end

  # The six real gemspecs load tools/versions by require_relative, so a helper loaded the same
  # way is where a subprocess would go to keep the gemspec's own text clean.
  test "rejects a gemspec whose require_relative helper runs the subprocess for it" do
    found = GemspecAudit.violations(File.join(FIXTURES, "helper_shells_out")).join("\n")

    assert_includes(found, "tools/gem_files.rb, loaded by the gemspec, runs a subprocess")
  end

  # Gem::Specification.load rescues an error raised while the gemspec evaluates, warns and
  # returns nil. The gate is red either way; what this pins is that the finding names the file
  # the way every other finding does, rather than surfacing as a NoMethodError on nil.
  test "names a gemspec that does not load instead of dereferencing nil" do
    found = nil
    _out, err = capture_io { found = GemspecAudit.violations(File.join(FIXTURES, "does_not_load")) }

    assert_equal(1, found.length, found.inspect)
    assert_match(
      %r{does_not_load/gems/dexpace-core/dexpace-core\.gemspec: gemspec did not load}, found.first,
    )
    assert_includes(err, "Invalid gemspec", "RubyGems' own warning still reaches stderr")
  end

  test "RubyGems sorts spec.files itself, so an unsorted literal loads sorted" do
    spec = Gem::Specification.load(
      File.join(FIXTURES, "unsorted_files/gems/dexpace-core/dexpace-core.gemspec"),
    )

    assert_equal(%w[lib/alpha.rb lib/zeta.rb], spec.files)
  end

  test "the gate task fails on a fixture and passes on the repository" do
    _out, err, status = rake(
      "gates:gemspec_audit", "DEXPACE_GATE_ROOT" => File.join(FIXTURES, "two_third_party"),
    )

    refute_predicate(status, :success?)
    assert_includes(err, "NFR-2")

    out, err, status = rake("gates:gemspec_audit")

    assert_predicate(status, :success?, err)
    assert_includes(out, "6 gemspecs")
  end
end
