# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/serde/json"

# P7-7's require-time floor assertion, exercised rather than restated (review round 1, R1-2): the
# entry file raises Dexpace::SeamError when the json it activated is below MINIMUM_JSON_VERSION,
# and nothing in this process can see that -- every gate row runs under the bundle's json, which
# is above the floor by construction, so json_test.rb's P7-7 case can only assert the constant, the
# running version and the gemspec agree. The raise is the whole content of the deviation and the
# claim the gem README makes for a stock Ruby, and deleting the block left every suite green.
#
# So the raise is driven in a CHILD process with the bundler environment stripped, pinning a json by
# exact version with `gem` before requiring the entry file. Two pins: the INTERPRETER'S DEFAULT json
# (2.6.3 / 2.7.2 / 2.9.1 / 2.18.0 on the four matrix rows -- below the floor on every one, which is
# exactly the unbundled `require "dexpace/serde/json"` P7-7 exists for), and the json this process
# is running, which is at or above the floor and must load and register. The first pin's expectation
# is computed from the same comparison the entry file makes, so a future Ruby whose default json
# clears the floor keeps the case meaningful instead of red. Only RUBYOPT (bundler's
# `-rbundler/setup`, which would re-enter the bundle and override the pin), RUBYLIB and the
# BUNDLE_*/BUNDLER_* keys are cleared; GEM_HOME and GEM_PATH stay, so the second pin finds the
# bundle's json under `bundle exec` and the interpreter's under a bare `ruby -I` run alike. A
# default gem is found through Gem.default_specifications_dir, independent of both.
class DexpaceSerdeJSONFloorTest < DexpaceTestCase
  GEM_ROOT = File.expand_path("../../../..", __dir__)
  # The core this process loaded, handed to the child explicitly (CoderKeywordsTest's shape).
  CORE_LIB = File.dirname($LOADED_FEATURES.grep(%r{/dexpace\.rb\z}).fetch(0))
  FLOOR = Gem::Version.new(Dexpace::Serde::JSON::MINIMUM_JSON_VERSION)

  UNBUNDLED = {
    "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil, "BUNDLE_LOCKFILE" => nil,
    "BUNDLE_BIN_PATH" => nil, "BUNDLER_VERSION" => nil, "BUNDLER_SETUP" => nil,
  }.freeze

  # One line: the outcome, the json that was active, and the message when the entry file refused.
  PROBE = <<~'RUBY'
    gem "json", "= #{ARGV.fetch(0)}"
    begin
      require "dexpace/serde/json"
      puts "LOADED json=#{JSON::VERSION} keys=#{Dexpace::Serde.registered_keys.inspect}"
    rescue Dexpace::SeamError => error
      puts "SEAM_ERROR json=#{JSON::VERSION} #{error.message}"
    end
  RUBY

  def pinned_require(version)
    command = [::RbConfig.ruby, "-w", "-I", CORE_LIB, "-Ilib", "-e", PROBE, version.to_s]
    IO.popen(UNBUNDLED, command, err: %i[child out], chdir: GEM_ROOT, &:read).chomp
  end

  # The json the interpreter ships, which is what an unbundled require activates.
  def default_json_stub
    Gem::Specification.default_stubs("json-*.gemspec").find { |s| s.name == "json" }
  end

  test "P7-7: the interpreter's default json, activated unbundled, is refused below the floor" do
    stub = default_json_stub

    refute_nil(stub, "json is a default gem on every supported Ruby")

    version = stub.version
    out = pinned_require(version)

    if version < FLOOR
      assert_match(/\ASEAM_ERROR json=#{Regexp.escape(version.to_s)} /, out)
      assert_includes(out, "requires json >= #{FLOOR}; json #{version} is active")
      assert_includes(out, "Add `gem \"json\", \">= #{FLOOR}\"`")
    else
      assert_equal("LOADED json=#{version} keys=[:json]", out)
    end
  end

  test "P7-7: a json at or above the floor loads, and the adapter registers itself" do
    version = Gem::Version.new(::JSON::VERSION)

    assert_operator(version, :>=, FLOOR, "this process runs the json the floor admits")
    assert_equal("LOADED json=#{version} keys=[:json]", pinned_require(version))
  end
end
