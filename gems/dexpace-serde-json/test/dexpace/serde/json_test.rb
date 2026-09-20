# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# NFR-15: the version a published artifact reports at runtime is the real one. Styleguide 12.7:
# no constant outside Dexpace::. NFR-2: this gem's one third-party dependency, `json >= 2.19.9`,
# declared here and nowhere else (design §3.4). P7-7: the floor asserted at require time, because
# bundler-audit runs in this repository's CI and never in a consumer's process.
class JSONTest < DexpaceTestCase
  # The namespaces are snapshotted around the require, so "defines nothing outside Dexpace" holds
  # whether this file loads alone or after the other five gems in one `rake test:gems` process,
  # where Dexpace already exists. Since phase 7a the entry file requires core (SeamError,
  # Serde.register, Native, MediaType) and `json`, `time` and `date` (the ISO-8601 defaults), so
  # those are loaded FIRST -- as core's own smoke suite preloads its stdlib features -- and the
  # delta the assertions read is exactly what this gem adds: `:JSON` beside its namespace, and
  # nothing at the top level or directly under Dexpace.
  require "dexpace"
  require "json"
  require "time"
  require "date"
  TOP_LEVEL_BEFORE = Object.constants
  NAMESPACE_BEFORE = defined?(Dexpace) ? Dexpace.constants(false) : []
  SIBLINGS_BEFORE = defined?(Dexpace::Serde) ? Dexpace::Serde.constants(false) : []
  require "dexpace/serde/json"
  TOP_LEVEL_ADDED = (Object.constants - TOP_LEVEL_BEFORE).freeze
  NAMESPACE_ADDED = (Dexpace.constants(false) - NAMESPACE_BEFORE).freeze
  SIBLINGS_ADDED = (Dexpace::Serde.constants(false) - SIBLINGS_BEFORE).freeze

  GEMSPEC = File.expand_path("../../../dexpace-serde-json.gemspec", __dir__)

  def spec = Gem::Specification.load(GEMSPEC)

  test "defines a semver VERSION string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::Serde::JSON::VERSION)
  end

  test "the VERSION matches the gemspec this gem is built from" do
    assert_equal(spec.version.to_s, Dexpace::Serde::JSON::VERSION)
  end

  test "defines nothing outside the Dexpace namespace" do
    assert_empty(TOP_LEVEL_ADDED, "top-level constants added by the entry file")
    assert_empty(NAMESPACE_ADDED, "constants added directly under Dexpace")
    assert_empty(SIBLINGS_ADDED - %i[JSON], "constants added beside this gem's namespace")
    assert_equal(%i[Codec MINIMUM_JSON_VERSION REQUIRED_CORE VERSION],
                 Dexpace::Serde::JSON.constants(false).sort,)
  end

  # The module shadows ::JSON inside its own namespace (see the CAUTION in the entry
  # file); the qualified form must still reach Ruby's own.
  test "the shadowing namespace does not hide Ruby's own JSON" do
    assert_equal("JSON", ::JSON.name)
    assert_equal("Dexpace::Serde::JSON", Dexpace::Serde::JSON.name)
    refute_same(::JSON, Dexpace::Serde::JSON)
  end

  test "NFR-2: the gemspec declares dexpace-core plus exactly one third-party gem, floored" do
    names = spec.runtime_dependencies.map(&:name).sort

    assert_equal(%w[dexpace-core json], names)
    assert_equal([">= 2.19.9"],
                 spec.runtime_dependencies.find { |d| d.name == "json" }.requirements_list,)
  end

  # P7-7. bundler-audit enforces the floor for a BUNDLED consumer in this repository's CI; it never
  # runs in a consumer's process. An unbundled `require "dexpace/serde/json"` on Ruby 3.4.10
  # activates the interpreter's default json 2.9.1, which has no JSON::Coder at all -- so without
  # this the failure is a NameError deep inside a codec, and the 2026 advisories the floor exists
  # for are silently unpatched. The constant and the gemspec state one number.
  test "P7-7: the floor is asserted at require time and names itself" do
    assert_equal("2.19.9", Dexpace::Serde::JSON::MINIMUM_JSON_VERSION)
    assert_operator(Gem::Version.new(::JSON::VERSION), :>=,
                    Gem::Version.new(Dexpace::Serde::JSON::MINIMUM_JSON_VERSION),)
    assert_equal([">= #{Dexpace::Serde::JSON::MINIMUM_JSON_VERSION}"],
                 spec.runtime_dependencies.find { |d| d.name == "json" }.requirements_list,)
  end

  test "the adapter registers itself against the seam under :json" do
    assert_includes(Dexpace::Serde.registered_keys, :json)
  end

  # The registry's core: argument is a TWO-SEGMENT PESSIMISTIC REQUIREMENT, never Dexpace::VERSION.
  # Phase 2's Registry#assert_core_version! matches it against /\A~>\s*(\d+)\.(\d+)\z/ and raises
  # Dexpace::InvalidArgumentError on anything else, so `core: Dexpace::VERSION` ("0.0.0") would make
  # `require "dexpace/serde/json"` raise at load. It must also AGREE with the string the gemspec
  # declares for dexpace-core -- the agreement gates:gemspec_audit checks from one side and nothing
  # checked from the other.
  test "REQUIRED_CORE is a ~> constraint and equals the gemspec's dexpace-core requirement" do
    declared = spec.runtime_dependencies.find { |d| d.name == "dexpace-core" }.requirements_list

    assert_match(/\A~>\s*\d+\.\d+\z/, Dexpace::Serde::JSON::REQUIRED_CORE)
    assert_equal(declared, [Dexpace::Serde::JSON::REQUIRED_CORE])
  end

  test "the module's two factories answer a fresh conforming codec each" do
    a = Dexpace::Serde::JSON.default
    b = Dexpace::Serde::JSON.build(max_nesting: 8)

    assert(Dexpace::Serde.conforms?(a))
    assert(Dexpace::Serde.conforms?(b))
    refute_same(a, Dexpace::Serde::JSON.default)
    assert_instance_of(Dexpace::Serde::JSON::Codec, b)
  end
end
