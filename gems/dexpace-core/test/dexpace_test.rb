# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "test_helper"

# NFR-15: the version a published artifact reports at runtime is the real one. Styleguide 12.7:
# no constant outside Dexpace::.
class DexpaceTest < DexpaceTestCase
  # The top-level namespace is snapshotted around the require, so "defines nothing outside
  # Dexpace" holds whether this file loads alone or after the other five gems in one
  # `rake test:gems` process, where Dexpace already exists. The two stdlib features core
  # requires (both on the require allowlist) are loaded first: the constants they define --
  # URI, StringScanner and strscan's ScanError alias -- are theirs, not the entry file's.
  require "uri"
  require "strscan"
  TOP_LEVEL_BEFORE = Object.constants
  NAMESPACE_BEFORE = defined?(Dexpace) ? Dexpace.constants(false) : []
  require "dexpace"
  TOP_LEVEL_ADDED = (Object.constants - TOP_LEVEL_BEFORE).freeze
  NAMESPACE_ADDED = (Dexpace.constants(false) - NAMESPACE_BEFORE).freeze

  test "defines a semver VERSION string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::VERSION)
  end

  test "the VERSION matches the gemspec this gem is built from" do
    gemspec = File.expand_path("../dexpace-core.gemspec", __dir__)
    spec = Gem::Specification.load(gemspec)

    assert_equal(spec.version.to_s, Dexpace::VERSION)
  end

  # Every public constant the surface manifest records, and the check that catches a file added
  # to lib/ and forgotten in the entry point.
  DOMAIN_MODEL = %i[
    Error InvalidArgumentError Model Builder HeaderSyntax HeaderName Headers Status Method
    Protocol MediaType PercentEncoding Query URL RequestOptions Request Response
  ].freeze

  test "defines nothing outside the Dexpace namespace" do
    assert_empty(TOP_LEVEL_ADDED - [:Dexpace], "top-level constants added by the entry file")
    assert_empty(NAMESPACE_ADDED - [:VERSION, *DOMAIN_MODEL], "constants added under Dexpace")
    assert_includes(Dexpace.constants(false), :VERSION)
  end
end
