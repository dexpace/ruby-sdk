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

  # A consumer requires "dexpace" and nothing else.
  test "requiring dexpace alone makes the whole domain model resolve" do
    assert_equal(Dexpace::Request, Dexpace.const_get(:Request))
    assert_equal(Dexpace::Headers, Dexpace.const_get(:Headers))
    assert_equal(Dexpace::Status, Dexpace.const_get(:Status))
    assert_equal(200, Dexpace::Status::OK.code)
  end

  test "every constant the manifest records is reachable from Dexpace" do
    DOMAIN_MODEL.each { |name| assert(Dexpace.const_defined?(name, false), "#{name} missing") }
    assert_empty(DOMAIN_MODEL - Dexpace.constants(false))
    %i[Headers Query RequestOptions Request Response].each do |name|
      assert(Dexpace.const_get(name).const_defined?(:Builder, false), "#{name}::Builder")
    end
  end

  # The shadowing name this SDK never defines: it would make a bare `rescue ArgumentError`
  # inside `module Dexpace` stop catching Ruby's own (deviation P1-3).
  test "never defines Dexpace::ArgumentError" do
    refute_includes(Dexpace.constants(false), :ArgumentError)
  end

  # Dexpace::Method shadows ::Method only inside core (the entry file's YARD block says so);
  # a consumer's top-level Method is still Ruby's, even after `include Dexpace`.
  test "Dexpace::Method does not shadow Ruby's Method for a consumer" do
    consumer = Class.new { include Dexpace }

    assert_equal(::Method, consumer.class_eval { Method })
    assert_instance_of(::Method, consumer.new.method(:to_s))
  end
end
