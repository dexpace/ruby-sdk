# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "json"

# NFR-15: the version a published artifact reports at runtime is the real one. Styleguide 12.7:
# no constant outside Dexpace::.
class JSONTest < DexpaceTestCase
  # The top-level namespace is snapshotted around the require, so "defines nothing outside
  # Dexpace" holds whether this file loads alone or after the other five gems in one
  # `rake test:gems` process, where Dexpace already exists. The intermediate namespace is
  # snapshotted the same way: a sibling this entry file placed beside its own constant --
  # `Dexpace::Serde::Shared` -- is outside the gem's namespace and inside nothing this suite
  # would otherwise look at.
  TOP_LEVEL_BEFORE = Object.constants
  NAMESPACE_BEFORE = defined?(Dexpace) ? Dexpace.constants(false) : []
  SIBLINGS_BEFORE = defined?(Dexpace::Serde) ? Dexpace::Serde.constants(false) : []
  require "dexpace/serde/json"
  TOP_LEVEL_ADDED = (Object.constants - TOP_LEVEL_BEFORE).freeze
  NAMESPACE_ADDED = (Dexpace.constants(false) - NAMESPACE_BEFORE).freeze
  SIBLINGS_ADDED = (Dexpace::Serde.constants(false) - SIBLINGS_BEFORE).freeze

  test "defines a semver VERSION string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::Serde::JSON::VERSION)
  end

  test "the VERSION matches the gemspec this gem is built from" do
    gemspec = File.expand_path("../../../dexpace-serde-json.gemspec", __dir__)
    spec = Gem::Specification.load(gemspec)

    assert_equal(spec.version.to_s, Dexpace::Serde::JSON::VERSION)
  end

  test "defines nothing outside the Dexpace namespace" do
    assert_empty(TOP_LEVEL_ADDED - [:Dexpace], "top-level constants added by the entry file")
    assert_empty(NAMESPACE_ADDED - %i[Serde], "constants added directly under Dexpace")
    assert_empty(SIBLINGS_ADDED - %i[JSON], "constants added beside this gem's namespace")
    assert_equal(%i[VERSION], Dexpace::Serde::JSON.constants(false).sort)
  end

  # The module shadows ::JSON inside its own namespace (see the CAUTION in the entry
  # file); the qualified form must still reach Ruby's own.
  test "the shadowing namespace does not hide Ruby's own JSON" do
    assert_equal("JSON", ::JSON.name)
    assert_equal("Dexpace::Serde::JSON", Dexpace::Serde::JSON.name)
    refute_same(::JSON, Dexpace::Serde::JSON)
  end
end
