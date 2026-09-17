# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CFG-14: the well-known key constants, plus the two names 5a's own wirings read.
class DexpaceConfigurationKeysTest < DexpaceTestCase
  test "CFG-14: the five well-known keys and the two wiring keys are frozen, non-empty Strings" do
    expected = {
      MAX_RETRY_ATTEMPTS: "MAX_RETRY_ATTEMPTS",
      LOG_LEVEL: "LOG_LEVEL",
      HTTP_PROXY: "HTTP_PROXY",
      HTTPS_PROXY: "HTTPS_PROXY",
      NO_PROXY: "NO_PROXY",
      MAX_MATERIALIZED_BYTES: "MAX_MATERIALIZED_BYTES",
      MAX_TRACKED_CONTEXTS: "MAX_TRACKED_CONTEXTS",
    }

    assert_equal(expected.keys.sort, Dexpace::Configuration::Keys.constants.sort)
    expected.each do |name, value|
      key = Dexpace::Configuration::Keys.const_get(name)

      assert_equal(value, key, name.to_s)
      assert_predicate(key, :frozen?, name.to_s)
    end
  end

  # OBS-35's embedded MUST: "The SDK MUST NOT bake in a default config key name." LOG_LEVEL is a
  # published name a caller may pass; nothing in core reads it, so no resolver falls back to it.
  test "CFG-14 / OBS-35: LOG_LEVEL is a published name that no resolver in core reads" do
    root = File.expand_path("../../../lib", __dir__)
    readers = Dir.glob("#{root}/**/*.rb").grep_v(%r{/configuration/keys\.rb\z}).select do |path|
      File.read(path).include?("LOG_LEVEL")
    end

    assert_empty(readers)
  end

  # The seven system-property names CFG-24 and CFG-26 read are the resolver's private business,
  # not well-known keys: CFG-14 does not name them and only the resolver reads them.
  test "CFG-14: the proxy system-property names are not published as keys" do
    Dexpace::Configuration::Keys.constants.each do |name|
      refute_match(/\./, Dexpace::Configuration::Keys.const_get(name))
    end
  end
end
