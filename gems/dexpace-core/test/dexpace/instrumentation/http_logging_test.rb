# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_config_source"
require_relative "../../../lib/dexpace/configuration"
require_relative "../../../lib/dexpace/instrumentation/http_logging"

# Exercises: OBS-34, OBS-35, CFG-14
#
# The three-level closed set, its tolerant parse, and the layered resolution that takes its
# configuration key as a REQUIRED argument: OBS-35's embedded MUST is "The SDK MUST NOT bake in
# a default config key name", so nothing here falls back to Configuration::Keys::LOG_LEVEL --
# that constant is a published name a caller MAY pass (5a's reconciliation, P5-36). Every
# Configuration below is built over FakeConfigSource seams and never the process environment.
class DexpaceInstrumentationHTTPLoggingTest < DexpaceTestCase
  HTTPLogging = Dexpace::Instrumentation::HTTPLogging
  Configuration = Dexpace::Configuration

  def configuration(environment: {}, properties: {}, overrides: {})
    Configuration.build(overrides: overrides, env_source: FakeConfigSource.new(environment),
                        property_source: FakeConfigSource.new(properties),)
  end

  test "OBS-34: exactly three levels, ordered, defaulting to NONE" do
    levels = [HTTPLogging::NONE, HTTPLogging::HEADERS, HTTPLogging::BODY]

    assert_equal(%i[none headers body], levels.map(&:name))
    assert_equal([0, 1, 2], levels.map(&:order))
    assert_same(HTTPLogging::NONE, HTTPLogging::DEFAULT)
    assert(HTTPLogging::BODY.at_least?(HTTPLogging::HEADERS))
    assert(HTTPLogging::BODY.at_least?(HTTPLogging::BODY))
    assert(HTTPLogging::HEADERS.at_least?(HTTPLogging::HEADERS))
    refute(HTTPLogging::HEADERS.at_least?(HTTPLogging::BODY))
    refute(HTTPLogging::NONE.at_least?(HTTPLogging::HEADERS))
    assert(HTTPLogging::NONE.at_least?(HTTPLogging::NONE))
  end

  test "OBS-34: the set is closed -- no constructor, no derivation, three frozen constants" do
    refute_respond_to(HTTPLogging, :new)
    refute_respond_to(HTTPLogging, :[])
    assert_raises(Dexpace::InvalidArgumentError) { HTTPLogging::BODY.with(order: 9) }
    [HTTPLogging::NONE, HTTPLogging::HEADERS, HTTPLogging::BODY].each do |level|
      assert_predicate(level, :frozen?)
    end
    refute_includes(HTTPLogging.constants, :ALL, "P5-16 names four constants and no fifth")
  end

  test "OBS-34: .of resolves a name by identity and refuses anything else" do
    assert_same(HTTPLogging::NONE, HTTPLogging.of(:none))
    assert_same(HTTPLogging::HEADERS, HTTPLogging.of(:headers))
    assert_same(HTTPLogging::BODY, HTTPLogging.of(:body))
    [:all, "headers", nil, 1].each do |name|
      assert_raises(Dexpace::InvalidArgumentError, name.inspect) { HTTPLogging.of(name) }
    end
  end

  # The chapter's own cases: `  Headers  ` and `HEADERS` resolve to the headers level; unset,
  # empty and garbage fall back to the default. The fold is `downcase` with no argument.
  test "OBS-35: .parse is case-insensitive, whitespace-trimmed, and falls back, never raises" do
    assert_same(HTTPLogging::HEADERS, HTTPLogging.parse("  Headers  "))
    assert_same(HTTPLogging::HEADERS, HTTPLogging.parse("HEADERS"))
    assert_same(HTTPLogging::BODY, HTTPLogging.parse("body\n"))
    assert_same(HTTPLogging::NONE, HTTPLogging.parse("none"))
    assert_same(HTTPLogging::NONE, HTTPLogging.parse(nil))
    assert_same(HTTPLogging::NONE, HTTPLogging.parse(""))
    assert_same(HTTPLogging::NONE, HTTPLogging.parse("   "))
    assert_same(HTTPLogging::NONE, HTTPLogging.parse("verbose"))
    assert_same(HTTPLogging::HEADERS, HTTPLogging.parse("garbage", default: HTTPLogging::HEADERS))
    assert_same(HTTPLogging::BODY, HTTPLogging.parse(:body))
    assert_same(HTTPLogging::HEADERS, HTTPLogging.parse("head\xFFers".b, default: HTTPLogging::HEADERS))
  end

  test "OBS-35: .resolve reads the caller's key through the chain's four tiers" do
    key = "SDK_HTTP_LOG"

    assert_same(HTTPLogging::HEADERS,
                HTTPLogging.resolve(configuration(environment: { key => "headers" }), key: key),)
    assert_same(HTTPLogging::BODY,
                HTTPLogging.resolve(configuration(properties: { "sdk.http.log" => " Body " }),
                                    key: key,),)
    assert_same(HTTPLogging::BODY,
                HTTPLogging.resolve(configuration(overrides: { key => "body" },
                                                  environment: { key => "headers" },), key: key,),)
    assert_same(HTTPLogging::NONE, HTTPLogging.resolve(configuration, key: key))
    assert_same(HTTPLogging::HEADERS,
                HTTPLogging.resolve(configuration, key: key, default: HTTPLogging::HEADERS),)
    garbage = configuration(environment: { key => "garbage" })

    assert_same(HTTPLogging::HEADERS,
                HTTPLogging.resolve(garbage, key: key, default: HTTPLogging::HEADERS),)
  end

  # P5-36: the key is required with no default, and Configuration::Keys::LOG_LEVEL is a name a
  # caller may pass -- which this case does, to show it works as an argument and only as one.
  test "OBS-35, CFG-14: the key keyword is required, and the published name is a caller's" do
    assert_raises(::ArgumentError) { HTTPLogging.resolve(configuration) }
    published = Configuration::Keys::LOG_LEVEL
    chain = configuration(environment: { published => "body" })

    assert_same(HTTPLogging::BODY, HTTPLogging.resolve(chain, key: published))
    assert_same(HTTPLogging::NONE, HTTPLogging.resolve(chain, key: "SOME_OTHER_KEY"))
  end
end
