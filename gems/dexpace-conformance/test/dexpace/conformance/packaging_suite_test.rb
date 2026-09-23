# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "tmpdir"
require_relative "../../test_helper"
require "dexpace/conformance"

# Appendix B.9's portable half, proven against deliberately non-conforming gem sets.
# NFR-1, NFR-2, NFR-3, NFR-10, NFR-11, NFR-13, NFR-14, NFR-15.
class DexpaceConformancePackagingSuiteTest < DexpaceTestCase # rubocop:disable Metrics/ClassLength -- one fixture gem set per assertion, each beside the test that drives it
  Suite = Dexpace::Conformance::PackagingSuite

  # Loaded constants standing in for installed gems' version metadata.
  module FakeGem
    VERSION = "0.1.0"

    module Adapter
      VERSION = "0.1.0"
    end

    module Stale
      VERSION = "0.0.9"
    end

    # A loaded module that reports no version at all: the NFR-15 defect, not an absent
    # antecedent.
    module NoVersion
    end
  end

  CORE = "dexpace-core"
  ADAPTER = "dexpace-serde-json"
  CONSTANTS = { CORE => "DexpaceConformancePackagingSuiteTest::FakeGem",
                ADAPTER => "DexpaceConformancePackagingSuiteTest::FakeGem::Adapter", }.freeze

  def spec(name, version, deps, ruby: ">= 3.2")
    ::Gem::Specification.new do |s|
      s.name = name
      s.version = version
      s.required_ruby_version = ruby
      deps.each { |dep| s.add_dependency(dep, ">= 0") }
    end
  end

  def conforming
    { CORE => spec(CORE, "0.1.0", []),
      ADAPTER => spec(ADAPTER, "0.1.0", [CORE, "json"]), }
  end

  def statuses(report) = report.results.to_h { |r| [r.assertion.ids.first, r.status] }

  def run_suite(specs, **over)
    defaults = { adapters: [ADAPTER], resolve: ->(name) { specs[name] }, constants: CONSTANTS,
                 versions: { CORE => "0.1.0", ADAPTER => "0.1.0" }, }
    Suite.run(**defaults, **over)
  end

  # ---- structure ----

  test "the suite covers the eight portable NFRs, one assertion each" do
    ids = Suite.assertions.flat_map(&:ids)

    assert_equal(%w[NFR-1 NFR-10 NFR-11 NFR-13 NFR-14 NFR-15 NFR-2 NFR-3], ids.sort)
    assert(ids.all? { |id| Dexpace::Conformance::Levels.known?(id) })
    refute_includes(ids, "NFR-8", "NFR-8 is vacuous by its own text and gets no assertion")
    refute_includes(ids, "NFR-5", "a coverage floor is a property of a BUILD, not of a unit")
  end

  # ---- NFR-1, NFR-2 ----

  test "a core with one runtime dependency fails NFR-1" do
    specs = conforming
    specs[CORE] = spec(CORE, "0.1.0", ["json"])

    assert_equal(:failed, statuses(run_suite(specs))["NFR-1"])
  end

  test "an adapter with two third-party dependencies fails NFR-2" do
    specs = conforming
    specs[ADAPTER] = spec(ADAPTER, "0.1.0", [CORE, "json", "oj"])

    assert_equal(:failed, statuses(run_suite(specs))["NFR-2"])
  end

  test "an adapter that does not declare the core at all fails NFR-2" do
    specs = conforming
    specs[ADAPTER] = spec(ADAPTER, "0.1.0", ["json"])

    assert_equal(:failed, statuses(run_suite(specs))["NFR-2"])
  end

  # ---- NFR-10 ----

  test "a unit declaring no runtime floor fails NFR-10" do
    specs = conforming
    specs[ADAPTER] = spec(ADAPTER, "0.1.0", [CORE, "json"], ruby: ">= 0")

    assert_equal(:failed, statuses(run_suite(specs))["NFR-10"])
  end

  # The half a gate asserting "every gemspec equals the global floor" gets wrong: a HIGHER floor
  # on one isolated unit is what NFR-10 asks for, not a defect.
  test "a higher floor on an isolated unit passes NFR-10" do
    specs = conforming
    specs[ADAPTER] = spec(ADAPTER, "0.1.0", [CORE, "json"], ruby: ">= 3.3")

    assert_equal(:passed, statuses(run_suite(specs))["NFR-10"])
  end

  test "a higher-floor unit that the core depends on fails NFR-10" do
    specs = { CORE => spec(CORE, "0.1.0", [ADAPTER]),
              ADAPTER => spec(ADAPTER, "0.1.0", [], ruby: ">= 3.3"), }

    assert_equal(:failed, statuses(run_suite(specs))["NFR-10"])
  end

  # ---- NFR-14, NFR-15 ----

  test "a published version disagreeing with the single source fails NFR-14" do
    report = run_suite(conforming, versions: { CORE => "0.2.0", ADAPTER => "0.1.0" })

    assert_equal(:failed, statuses(report)["NFR-14"])
  end

  # R0-2: the assertion's own comment promises this and the first cut passed instead, because an
  # empty map skipped every unit and nothing mismatched. "Nobody told us" is not evidence of a
  # single source, and NFR-14 is a SHOULD, so the vacuity is recorded without blocking the report.
  test "with no single source named, NFR-14 is vacuous rather than a pass" do
    report = run_suite(conforming, versions: {})

    assert_equal(:vacuous, statuses(report)["NFR-14"])
    assert_includes(report.to_s, "no single source of truth was named for any unit")
    assert_predicate(report, :passed?, "NFR-14 is a SHOULD, so its vacuity does not block")
  end

  # The partial case the comment names: a source that states some units states nothing about the
  # rest, so those are skipped rather than failed -- the declaration is the driver's.
  test "a single source naming only some units checks those and skips the rest" do
    report = run_suite(conforming, versions: { CORE => "0.1.0" })

    assert_equal(:passed, statuses(report)["NFR-14"])
  end

  test "a runtime version disagreeing with the gemspec fails NFR-15" do
    constants = CONSTANTS.merge(ADAPTER => "DexpaceConformancePackagingSuiteTest::FakeGem::Stale")

    assert_equal(:failed, statuses(run_suite(conforming, constants: constants))["NFR-15"])
  end

  # The mutation that proves this is not the assertion a green 0.0.0 tree would pass: a
  # not-a-placeholder check alone passes at 0.0.0, which is the version every gem here carries.
  test "NFR-15 compares against the gemspec, so a 0.0.0 gemspec is not a free pass" do
    specs = { CORE => spec(CORE, "0.0.0", []) }
    report = Suite.run(adapters: [], resolve: ->(name) { specs[name] },
                       constants: { CORE => "DexpaceConformancePackagingSuiteTest::FakeGem" },)

    assert_equal(:failed, statuses(report)["NFR-15"],
                 "0.1.0 reported against a 0.0.0 gemspec must fail",)
  end

  test "a LOADED gem that defines no VERSION fails NFR-15 rather than vacuating it" do
    constants = CONSTANTS.merge(ADAPTER =>
      "DexpaceConformancePackagingSuiteTest::FakeGem::NoVersion")

    assert_equal(:failed, statuses(run_suite(conforming, constants: constants))["NFR-15"])
  end

  # ---- vacuity ----

  test "an uninstalled gem is vacuous, never failed" do
    report = Suite.run(adapters: [ADAPTER], resolve: ->(_name) {}, constants: CONSTANTS)

    assert_equal([:vacuous], report.results.map(&:status).uniq)
  end

  # R0-4: every other case here supplies its own `resolve:`, so the SHIPPED default -- the one a
  # real driver gets, and a locked public constant -- ran in no test at all. Its rescue is what
  # turns "this gem is not installed" into the :vacuous the suite's contract promises rather than
  # the Gem::MissingSpecError a bare `find_by_name` raises, which Runner would report :error.
  test "the shipped default resolve answers vacuous for a gem that is not installed" do
    absent = "dexpace-no-such-gem-#{Process.pid}"
    adapter = "#{absent}-adapter"
    report = Suite.run(core: absent, adapters: [adapter],
                       versions: { absent => "0.0.0", adapter => "0.0.0" },)

    assert_equal([:vacuous], report.results.map(&:status).uniq)
    assert_includes(report.to_s, "#{absent} is not installed")
  end

  test "an unloaded constant is vacuous, never failed" do
    report = run_suite(conforming, constants: { CORE => "NotLoaded::Anywhere" })

    assert_equal(:vacuous, statuses(report)["NFR-15"])
  end

  # ---- NFR-3, NFR-11, NFR-13, over a seeded shipped tree ----

  def seeded(lib:, sig:)
    root = Dir.mktmpdir("dexpace-packaging")
    lib.each { |path, body| write(File.join(root, "lib", path), body) }
    sig.each { |path, body| write(File.join(root, "sig", path), body) }
    root
  end

  def write(path, body)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
  end

  HEADED = "# frozen_string_literal: true\n# SPDX-License-Identifier: MIT\n\nmodule Dexpace\nend\n"
  BARE = "module Dexpace\nend\n"

  def shipped(lib:, sig:)
    root = seeded(lib: lib, sig: sig)
    run_suite(conforming, adapters: [], sig_roots: { CORE => File.join(root, "sig") })
  end

  test "a shipped lib file with no signature beside it fails NFR-3" do
    report = shipped(lib: { "dexpace.rb" => BARE, "dexpace/extra.rb" => BARE },
                     sig: { "dexpace.rbs" => HEADED },)

    assert_equal(:failed, statuses(report)["NFR-3"])
  end

  test "a one-for-one lib and sig tree passes NFR-3" do
    report = shipped(lib: { "dexpace.rb" => BARE }, sig: { "dexpace.rbs" => HEADED })

    assert_equal(:passed, statuses(report)["NFR-3"])
  end

  test "a signature naming an async-framework type fails NFR-11" do
    leaking = "# SPDX-License-Identifier: MIT\nmodule Dexpace\n  A: Async::Task\nend\n"
    report = shipped(lib: { "dexpace.rb" => BARE }, sig: { "dexpace.rbs" => leaking })

    assert_equal(:failed, statuses(report)["NFR-11"])
  end

  # The negative control that matters: core's OWN Dexpace::Async::Future is not a leak, and a
  # scan matching the bare namespace would call it one.
  test "the core's own Dexpace::Async namespace is not an async-framework leak" do
    own = "# SPDX-License-Identifier: MIT\nmodule Dexpace\n  A: Dexpace::Async::Future\nend\n"
    report = shipped(lib: { "dexpace.rb" => BARE }, sig: { "dexpace.rbs" => own })

    assert_equal(:passed, statuses(report)["NFR-11"])
  end

  test "a mention inside a comment is not an async-framework leak" do
    commented = "# SPDX-License-Identifier: MIT\n# see Async::Task\nmodule Dexpace\nend\n"
    report = shipped(lib: { "dexpace.rb" => BARE }, sig: { "dexpace.rbs" => commented })

    assert_equal(:passed, statuses(report)["NFR-11"])
  end

  test "a shipped signature with no SPDX header fails NFR-13" do
    report = shipped(lib: { "dexpace.rb" => BARE }, sig: { "dexpace.rbs" => BARE })

    assert_equal(:failed, statuses(report)["NFR-13"])
    assert_includes(report.to_s, "a RuboCop cop cannot reach .rbs")
  end

  test "a shipped signature carrying the header passes NFR-13" do
    report = shipped(lib: { "dexpace.rb" => BARE }, sig: { "dexpace.rbs" => HEADED })

    assert_equal(:passed, statuses(report)["NFR-13"])
  end

  # The assertion must discriminate against the REAL tree too, not only against a fixture: 278
  # shipped .rbs files carry no header today, which is the gap phase 10's inbound list owns.
  test "NFR-13 against this repository's own shipped signatures reports the real gap" do
    root = File.expand_path("../../../..", __dir__)
    report = run_suite(conforming, adapters: [],
                                   sig_roots: { CORE => File.join(root, "dexpace-core", "sig") },)

    assert_equal(:failed, statuses(report)["NFR-13"],
                 "an unconditional vacuity here would check nothing for anyone",)
  end
end
