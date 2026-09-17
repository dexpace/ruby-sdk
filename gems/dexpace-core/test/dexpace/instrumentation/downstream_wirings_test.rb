# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../support/warning_capture"
require_relative "../../support/fake_config_source"
# This suite crosses four subsystems 5b only modifies -- close_quietly, Hooks, the proxy
# resolver and Configuration::Keys -- so it loads the whole gem rather than hand-picking files.
require "dexpace"

# Exercises: OBS-20, CFG-21, CFG-24, CFG-25, CFG-14, SEAM-25
#
# The four wirings phase 2, phase 3b and phase 5a left for §8.1's facade: close_quietly's second
# disposal route (phase 2's postponement, completed), Hooks.notify's per-dropped-failure
# diagnostic (phase 2's option, taken), the configuration diagnostic beside the proxy resolver's
# Kernel#warn (P5-8, discharged) and the one Configuration::Keys name the body-logging caps'
# pick-up adds. Every Configuration here is built over FakeConfigSource seams; no test reads the
# process environment. It carries no lib/ mirror and says so.
#
# Split into nested classes under Metrics/ClassLength: the two phase-2 routes, the 5a wiring.
class DexpaceInstrumentationDownstreamWiringsTest < DexpaceTestCase
  Logger = Dexpace::Instrumentation::Logger
  Events = Dexpace::Instrumentation::Events
  Keys = Dexpace::Instrumentation::Keys

  # A closeable whose close fails.
  class Raising
    def close
      raise ::IOError, "close failure"
    end
  end

  test "close_quietly's second route: without onto:, the failure is a close diagnostic" do
    sink = RecordingSink.new

    assert_nil(Dexpace.close_quietly(Raising.new, logger: Logger.build(sink: sink)))
    assert_equal(1, sink.entries.size)
    assert_equal(:warn, sink.entries.first.severity)
    payload = sink.payloads.first

    assert_equal(Events::INSTRUMENTATION_CLOSE, payload[Keys::EVENT])
    assert_equal("IOError: close failure", payload[Keys::CAUSE])
  end

  # 4b's interface table anticipated this: "Phase 5 adds the http.instrumentation.* diagnostic
  # for the onto:-absent case and completes the pair of routes phase 2 postponed". What survives
  # is the RETURN contract, CFG-21's null-safety, and the first route is untouched: with onto:
  # the failure goes to the trail and NOT to the logger -- two routes, never both.
  test "close_quietly: the default logger reports nothing, and onto: still takes the trail alone" do
    sink = RecordingSink.new
    primary = ::RuntimeError.new("primary")

    assert_nil(Dexpace.close_quietly(Raising.new))
    assert_nil(Dexpace.close_quietly(Raising.new, onto: primary, logger: Logger.build(sink: sink)))
    assert_equal(1, Dexpace.suppressed(primary).size)
    assert_kind_of(::IOError, Dexpace.suppressed(primary).first)
    assert_empty(sink.entries, "with onto: the trail is the route, and the logger sees nothing")
    assert_nil(Dexpace.close_quietly(nil, logger: Logger.build(sink: sink)))
    assert_nil(Dexpace.close_quietly(::Object.new, logger: Logger.build(sink: sink)))
    assert_empty(sink.entries)
  end

  # OBS-20 at the wiring: a sink that raises cannot turn a cleanup into a failure.
  test "close_quietly's diagnostic is contained: a raising sink still yields nil" do
    exploding = ::Object.new
    %i[debug? info? warn? error?].each { |name| exploding.define_singleton_method(name) { true } }
    %i[debug info warn error].each do |name|
      exploding.define_singleton_method(name) { |*| raise "sink failure" }
    end

    assert_nil(Dexpace.close_quietly(Raising.new, logger: Logger.build(sink: exploding)))
  end

  # Hooks is a private_constant (P2-15): a qualified Dexpace::Hooks raises NameError, so
  # const_get reaches it, which is how phase 4b drove the same method.
  test "Hooks.notify: each failure after the first is a hook diagnostic, beside the trail" do
    sink = RecordingSink.new
    first = ->(_) { raise ::IOError, "first hook error" }
    second = ->(_) { raise ::ArgumentError, "second hook error" }
    third = ->(_) { raise "third hook error" }
    ran = []
    hooks = [first, second, ->(argument) { ran << argument }, third]

    error = assert_raises(::IOError) do
      Dexpace.const_get(:Hooks).notify(hooks, :arg, logger: Logger.build(sink: sink))
    end

    assert_equal("first hook error", error.message)
    assert_equal([:arg], ran, "every hook still runs")
    assert_equal(%w[ArgumentError RuntimeError], Dexpace.suppressed(error).map { |e| e.class.name },
                 "the trail is not replaced",)
    assert_equal(2, sink.entries.size, "one diagnostic per dropped failure, none for the first")
    assert_equal([Events::INSTRUMENTATION_HOOK] * 2,
                 sink.payloads.map { |payload| payload[Keys::EVENT] },)
    assert_equal(["ArgumentError: second hook error", "RuntimeError: third hook error"],
                 sink.payloads.map { |payload| payload[Keys::CAUSE] },)
  end

  test "Hooks.notify: with no logger nothing is emitted, and a clean run emits nothing either" do
    sink = RecordingSink.new
    seen = []

    assert_raises(::IOError) do
      Dexpace.const_get(:Hooks).notify([->(_) { raise ::IOError }, ->(_) { raise "x" }], nil)
    end
    assert_nil(Dexpace.const_get(:Hooks).notify([->(argument) { seen << argument }], 1,
                                                logger: Logger.build(sink: sink),))
    assert_equal([1], seen)
    assert_empty(sink.entries)
  end

  # P5-8 and the body-logging caps' key.
  class ConfigurationWiringTest < DexpaceTestCase
    Logger = Dexpace::Instrumentation::Logger
    Events = Dexpace::Instrumentation::Events
    Keys = Dexpace::Instrumentation::Keys
    ConfigKeys = Dexpace::Configuration::Keys

    def configuration(environment: {}, properties: {})
      Dexpace::Configuration.build(env_source: FakeConfigSource.new(environment),
                                   property_source: FakeConfigSource.new(properties),)
    end

    # CFG-25: a proxy URL with no explicit port warns. Both the warning and the diagnostic are
    # observed -- the warning through phase 2's WarningCapture, never a second capture -- and the
    # diagnostic carries the warning's text.
    test "P5-8, CFG-25: the proxy resolver emits a config diagnostic beside its warning" do
      sink = RecordingSink.new
      chain = configuration(environment: { ConfigKeys::HTTPS_PROXY => "http://proxy.example.com" })

      warnings = WarningCapture.record do
        assert_nil(Dexpace::Proxy.resolve(chain, logger: Logger.build(sink: sink)))
      end

      assert_equal(1, warnings.size)
      assert_match(/\A\[dexpace\] proxy URL .* has no explicit port/, warnings.first)
      assert_equal(1, sink.entries.size)
      payload = sink.payloads.first

      assert_equal(Events::INSTRUMENTATION_CONFIG, payload[Keys::EVENT])
      assert_equal(warnings.first.delete_prefix("[dexpace] ").chomp, payload[Keys::MESSAGE])
      refute(payload.key?(Keys::CAUSE), "a warning carries a message and no throwable")
    end

    test "P5-8, CFG-24: a property-layer port problem takes the same route; the warning stays" do
      sink = RecordingSink.new
      chain = configuration(properties: { "https.proxyHost" => "h", "https.proxyPort" => "x" })

      warnings = WarningCapture.record do
        assert_nil(Dexpace::Proxy.resolve(chain, logger: Logger.build(sink: sink)))
      end

      assert_equal(1, warnings.size)
      assert_equal(1, sink.entries.size)
      assert_match(/https\.proxyPort/, sink.payloads.first[Keys::MESSAGE])
    end

    # P5-103 (review round 1's R1-1): the warning shows the URL, a proxy URL is the one
    # configuration value that carries a credential, and the diagnostic carries the warning's
    # text under a key the redactor does not reserve -- so the round-1 review found `user:secret`
    # in the sink on every malformed-URL path. The URL is now rendered through the redactor's
    # total form for both channels, and CFG-24's grammar rule covers the scheme-less spelling the
    # redactor reads as an opaque part. The assertion is the chapter's negative: the credential
    # appears NOWHERE, in the warning or in any payload.
    test "P5-103, CFG-24, CFG-25, OBS-11: a proxy credential reaches neither channel" do
      ["http://user:secret@proxy.corp", "http://user:secret@proxy.corp:99999",
       "http://user:secret@proxy.corp:abc", "http://user:secret@proxy corp:3128",
       "http://user:secret@:3128", "http://a@user:secret@proxy.corp:3128",
       "user:secret@proxy.corp:3128", "//user:secret@proxy.corp",
       "http://user:secret@proxy.corp?token=T",].each do |url|
        sink = RecordingSink.new
        chain = configuration(environment: { ConfigKeys::HTTPS_PROXY => url })

        warnings = WarningCapture.record do
          assert_nil(Dexpace::Proxy.resolve(chain, logger: Logger.build(sink: sink)), url)
        end

        assert_equal(1, warnings.size, url)
        assert_equal(1, sink.entries.size, url)
        message = sink.payloads.first[Keys::MESSAGE]

        assert_includes(warnings.first, "***:***@", url)
        assert_includes(message, "***:***@", url)
        refute_includes(warnings.first, "secret", url)
        refute_includes(warnings.first, "user:", url)
        refute_includes(sink.payloads.inspect, "secret", url)
        refute_includes(sink.payloads.inspect, "user:", url)
        refute_includes(sink.payloads.inspect, "token=T", url)
      end
    end

    # The parser's own message repeats the value it rejected, so it is not quoted; a reader
    # still sees the (redacted) URL and the problem, and 5a's phrases are untouched.
    test "P5-103: a value the parser rejects is named once, redacted, without the parser's text" do
      sink = RecordingSink.new
      chain = configuration(environment: { ConfigKeys::HTTPS_PROXY => "http://user:secret@h:abc" })

      warnings = WarningCapture.record do
        assert_nil(Dexpace::Proxy.resolve(chain, logger: Logger.build(sink: sink)))
      end

      expected = "proxy URL \"http://***:***@h:abc\" is not a URI"

      assert_equal("[dexpace] #{expected}", warnings.first.chomp)
      assert_equal(expected, sink.payloads.first[Keys::MESSAGE])
      refute_includes(warnings.first, "bad URI")
    end

    test "P5-8: without a logger the warning is the only output, and a valid proxy warns nothing" do
      sink = RecordingSink.new
      bad = configuration(environment: { ConfigKeys::HTTPS_PROXY => "nope" })
      warnings = WarningCapture.record { assert_nil(Dexpace::Proxy.resolve(bad)) }

      assert_equal(1, warnings.size)
      good = configuration(environment: { ConfigKeys::HTTPS_PROXY => "http://h:3128" })
      proxy = Dexpace::Proxy.resolve(good, logger: Logger.build(sink: sink))

      assert_equal("h", proxy.host)
      assert_equal(3128, proxy.port)
      assert_empty(sink.entries)
    end

    test "the body-logging caps' key: LOG_PREVIEW_BYTES is the eighth key, LOG_LEVEL is 5a's" do
      assert_equal("LOG_PREVIEW_BYTES", ConfigKeys::LOG_PREVIEW_BYTES)
      assert_equal("LOG_LEVEL", ConfigKeys::LOG_LEVEL)
      assert_predicate(ConfigKeys::LOG_PREVIEW_BYTES, :frozen?)
      assert_equal(8, ConfigKeys.constants.size)
      # The reference default is the CALLER's, resolved through 5a's typed accessor and never
      # baked into a 5b signature (the plan's open question 5).
      assert_equal(8192, configuration.integer(ConfigKeys::LOG_PREVIEW_BYTES, default: 8 * 1024))
      assert_equal(64, configuration(environment: { ConfigKeys::LOG_PREVIEW_BYTES => "64" })
                        .integer(ConfigKeys::LOG_PREVIEW_BYTES, default: 8 * 1024),)
    end
  end
end
