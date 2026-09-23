# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The MUST-level vacuity blocker's level map: generated from appendix C and never allowed to drift
# from it. Appendix C is FROZEN; the tool under test reads it and writes only levels.rb. NFR-17;
# design R3.
require_relative "../support/gate_case"
require_relative "../../tools/requirement_levels"
require_relative "../../gems/dexpace-conformance/lib/dexpace/conformance"

class RequirementLevelsTest < GateCase
  PREFIXES = %w[SEAM HTTP IO BODY CTX PIPE RECOV RETRY REDIR AUTH PAGE SSE SERDE OBS CFG
                TRANSPORT ASYNC XCUT NFR].freeze

  test "the committed map equals a fresh parse of appendix C" do
    assert_equal(RequirementLevels.parse, Dexpace::Conformance::Levels::OF,
                 "levels.rb is stale: run `ruby tools/requirement_levels.rb`",)
  end

  test "appendix C yields 645 ids over the 19 prefixes and every id has a level" do
    map = RequirementLevels.parse

    assert_equal(645, map.size,
                 "CLAUDE.md: 645 numbered requirements; the spec is frozen, so a change here is " \
                 "a human decision",)
    assert_equal(PREFIXES.sort, map.keys.map { |id| id.sub(/-\d+\z/, "") }.uniq.sort)
    assert_equal(%i[may must should], map.values.uniq.sort)
  end

  # `MUST NOT` is a MUST with a negated predicate, and appendix C holds exactly one.
  test "MUST NOT is a must" do
    assert_equal(:must, RequirementLevels::LEVEL.fetch("MUST NOT"))
  end

  test "the tool never writes appendix C" do
    before = RequirementLevels::SOURCE.read
    RequirementLevels.render(RequirementLevels.parse)

    assert_equal(before, RequirementLevels::SOURCE.read)
  end

  # The failing fixture: one flipped level is a diff, not a pass.
  test "a map with one level flipped does not equal the committed file" do
    stale = RequirementLevels.render(RequirementLevels.parse.merge("ASYNC-4" => :should))

    refute_equal(RequirementLevels::TARGET.read, stale)
  end

  # Both exits, which the name always claimed and only the first half ever checked: a --check that
  # returned 0 unconditionally passed this test until the phase's own mutation pass caught it. The
  # stale file is written to a temp dir and named on the command line, so nothing under gems/ is
  # touched and the failing half needs no fixture tree.
  test "--check exits zero on the committed file and non-zero on a stale one" do
    assert(system(RbConfig.ruby, "tools/requirement_levels.rb", "--check", chdir: ROOT),
           "the committed levels.rb is stale",)

    Dir.mktmpdir do |dir|
      stale = File.join(dir, "levels.rb")
      rendered = RequirementLevels.render(RequirementLevels.parse)
      File.write(stale, rendered.sub("=> :must", "=> :may"))

      refute(system(RbConfig.ruby, "tools/requirement_levels.rb", "--check", stale, chdir: ROOT),
             "--check accepted a file that differs from a fresh render",)
    end
  end

  test "every id any suite declares is one appendix C knows" do
    suites = [Dexpace::Conformance::InvariantSuite, Dexpace::Conformance::PackagingSuite,
              Dexpace::Conformance::CodecSuite, Dexpace::Conformance::ExecutorSuite,
              Dexpace::Conformance::TransportSuite,]
    declared = Dexpace::Conformance::Aggregate.by_requirement_id(suites).keys

    assert_empty(declared.reject { |id| Dexpace::Conformance::Levels.known?(id) })
  end

  # An unknown id never blocks a report, so a typo in an assertion's `ids:` would be invisible.
  test "an id appendix C does not hold answers :unknown rather than raising" do
    assert_equal(:unknown, Dexpace::Conformance::Levels.of("XCUT-999"))
    refute(Dexpace::Conformance::Levels.must?("XCUT-999"))
  end
end
