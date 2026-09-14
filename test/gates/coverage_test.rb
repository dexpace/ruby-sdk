# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# NFR-5: an aggregate line-coverage floor of 80% across the library units, wired into the
# default build. At phase 0 the tracked set is twelve files -- six entry files and six version
# files -- every one of them executed by its gem's smoke suite, so the floor is armed and passes
# on its merits rather than being switched off. It becomes load-bearing in phase 1.
class CoverageTest < GateCase
  test "the floor is 80 and is not conditioned on anything" do
    body = File.read(File.join(ROOT, "test/support/coverage.rb"))

    assert_includes(body, "minimum_coverage 80")
    refute_match(/if .*minimum_coverage|minimum_coverage.*if /, body)
  end

  test "test support, tasks and fixtures are excluded from the aggregate" do
    body = File.read(File.join(ROOT, "test/support/coverage.rb"))

    %w[/test/ /tasks/ /.rubocop/ /fixtures/].each { |path| assert_includes(body, path) }
  end

  test "an uncovered library file fails the floor" do
    # tmp/ is gitignored and matches none of the filters above, which is the point: a fixture
    # under test/fixtures/ would be filtered out, leaving an empty set that SimpleCov reports as
    # 100% -- a green gate over nothing.
    dir = File.join(ROOT, "tmp/coverage_fixture/lib")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "uncovered.rb"), <<~RUBY)
      # frozen_string_literal: true
      # SPDX-License-Identifier: MIT

      # Deliberately untested: the input that proves the floor fails rather than warns.
      module UncoveredFixture
        def self.never_called
          :unreachable
        end
      end
    RUBY

    _out, err, status = Open3.capture3(
      { "COVERAGE" => "1", "COVERAGE_TRACK" => "tmp/coverage_fixture/lib/**/*.rb" },
      "ruby", "-Itest", "-rsupport/coverage", "-e", "", chdir: ROOT,
    )

    refute_predicate(status, :success?)
    assert_includes(err, "minimum coverage")
  ensure
    FileUtils.rm_rf(File.join(ROOT, "tmp/coverage_fixture"))
  end
end
