# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/fake_clock"
require_relative "../../support/fake_config_source"
require_relative "../../support/recording_sink"

# Exercises: RECOV-34, RETRY-12, RETRY-13, RETRY-14, RETRY-21, RETRY-41, RETRY-42, RECOV-30,
# CFG-14, OBS-20, SEAM-29, P6-6, P6-57, P6-59
#
# The one retry configuration: its defaults are Policy's constants, its validation is RECOV-34
# clause by clause, its collections are copied and frozen, and its max_retries is the first
# reader of 5a's Keys::MAX_RETRY_ATTEMPTS. Hermetic: every test that consults the process slot
# installs a FakeConfigSource env seam and resets the slot in teardown (5a's rule), so a host
# MAX_RETRY_ATTEMPTS variable cannot change the answer.
class DexpaceResilienceRetrySettingsTest < DexpaceTestCase
  Settings = Dexpace::Resilience::RetrySettings
  Policy = Dexpace::Resilience::Policy
  KEY = Dexpace::Configuration::Keys::MAX_RETRY_ATTEMPTS

  # The hermetic slot, shared by the nested classes.
  module Hermetic
    def setup
      super
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new }
    end

    def teardown
      Dexpace.reset_config!
      super
    end
  end
  include Hermetic

  test "RECOV-34 / RETRY-12: the defaults are Policy's shared constants; the object is frozen" do
    settings = Settings.build

    assert_in_delta(Policy::DEFAULT_INITIAL_DELAY, settings.initial_delay)
    assert_in_delta(Policy::DEFAULT_MULTIPLIER, settings.multiplier)
    assert_in_delta(Policy::DEFAULT_MAX_DELAY, settings.max_delay)
    assert_in_delta(Policy::DEFAULT_JITTER, settings.jitter)
    assert_equal(Policy::DEFAULT_MAX_RETRIES, settings.max_retries)
    assert_in_delta(0.0, settings.total_timeout, 0.0, "unbounded by default")
    assert_equal(Policy::DEFAULT_RETRYABLE_STATUSES, settings.retryable_statuses)
    assert_nil(settings.pacing_header_order)
    assert_same(::Random, settings.random)
    assert_same(Dexpace::Clock::SYSTEM, settings.clock)
    assert_predicate(settings, :frozen?)
    refute_respond_to(Settings, :new)
  end

  test "RETRY-13: backoff_arguments is exactly the keyword set Policy.backoff_delay takes" do
    settings = Settings.build(initial_delay: 1, multiplier: 3, max_delay: 9, jitter: 0)
    arguments = settings.backoff_arguments

    assert_equal(%i[initial_delay multiplier max_delay jitter random], arguments.keys)
    assert_in_delta(3.0, Policy.backoff_delay(2, **arguments), 0.0, "1 * 3**1 = 3, uncapped")
    assert_in_delta(9.0, Policy.backoff_delay(3, **arguments), 0.0, "1 * 3**2 = 9, at the cap")
  end

  test "RETRY-21: header_order is the caller's list, else the shared default" do
    assert_same(Policy::DEFAULT_PACING_HEADER_ORDER, Settings.build.header_order)
    custom = Settings.build(pacing_header_order: %w[X-RateLimit-Reset])

    assert_equal(%w[X-RateLimit-Reset], custom.header_order)
    assert_equal(%w[X-RateLimit-Reset], custom.pacing_header_order)
  end

  # RECOV-34's validation clauses.
  class ValidationTest < DexpaceTestCase
    include Hermetic

    test "RECOV-34: durations are non-negative, finite and within the ~292-year ceiling" do
      %i[initial_delay max_delay total_timeout].each do |member|
        assert_raises(Dexpace::InvalidArgumentError, member) { Settings.build(member => -1.0) }
        assert_raises(Dexpace::InvalidArgumentError, member) { Settings.build(member => nil) }
        assert_raises(Dexpace::InvalidArgumentError, member) { Settings.build(member => "1") }
        assert_raises(Dexpace::InvalidArgumentError, member) do
          Settings.build(member => ::Float::INFINITY)
        end
        assert_raises(Dexpace::InvalidArgumentError, member) do
          Settings.build(member => ::Float::NAN)
        end
        assert_raises(Dexpace::InvalidArgumentError, member) do
          Settings.build(member => 9_223_372_037.0) # one second past the ceiling
        end
        assert_in_delta(9_223_372_036.0,
                        Settings.build(member => 9_223_372_036).public_send(member),)
        assert_in_delta(0.0, Settings.build(member => 0).public_send(member))
      end
    end

    test "RECOV-34: the multiplier is >= 1.0 and finite" do
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(multiplier: 0.5) }
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(multiplier: 0) }
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(multiplier: ::Float::INFINITY) }
      assert_in_delta(1.0, Settings.build(multiplier: 1).multiplier)
    end

    test "RECOV-34: the jitter lies within [0.0, 1.0]" do
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(jitter: 1.5) }
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(jitter: -0.1) }
      assert_in_delta(0.0, Settings.build(jitter: 0).jitter)
      assert_in_delta(1.0, Settings.build(jitter: 1).jitter)
    end

    test "RECOV-34: max_retries is a non-negative Integer; zero disables retries" do
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(max_retries: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(max_retries: 1.5) }
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(max_retries: nil) }
      assert_equal(0, Settings.build(max_retries: 0).max_retries)
    end

    test "SEAM-29: every refusal names its member" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Settings.build(max_delay: -1) }

      assert_includes(error.message, "max_delay")
      error = assert_raises(Dexpace::InvalidArgumentError) { Settings.build(jitter: 2) }

      assert_includes(error.message, "jitter")
    end

    test "RECOV-34: retryable_statuses and pacing_header_order are copied and deep-frozen" do
      statuses = ::Set[500]
      order = [+"Retry-After"]
      settings = Settings.build(retryable_statuses: statuses, pacing_header_order: order)
      statuses << 599
      order << "retry-after-ms"
      order.first << "-mutated"

      assert_equal(::Set[500], settings.retryable_statuses)
      assert_equal(%w[Retry-After], settings.pacing_header_order)
      assert_predicate(settings.retryable_statuses, :frozen?)
      assert_predicate(settings.pacing_header_order, :frozen?)
      assert_predicate(settings.pacing_header_order.first, :frozen?)
      refute_predicate(statuses, :frozen?, "the caller's own collection is untouched")
    end

    test "RECOV-34: retryable_statuses accepts any Integer collection and refuses anything else" do
      assert_equal(::Set[1, 2], Settings.build(retryable_statuses: [1, 2, 2]).retryable_statuses)
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(retryable_statuses: %w[500]) }
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(retryable_statuses: 500) }
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(pacing_header_order: "x") }
      assert_raises(Dexpace::InvalidArgumentError) { Settings.build(pacing_header_order: [:x]) }
    end
  end

  # RETRY-12 / P6-6: the configured key, and #with.
  class ConfiguredTest < DexpaceTestCase
    include Hermetic

    test "RETRY-12 / P6-6: max_retries defaults through Keys::MAX_RETRY_ATTEMPTS when not passed" do
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "7") }

      assert_equal(7, Settings.build.max_retries)
      assert_equal("MAX_RETRY_ATTEMPTS", KEY, "5a's name, its first reader here")
    end

    test "RETRY-12 / P6-6: an explicit max_retries: wins over the configured key, zero included" do
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "7") }

      assert_equal(1, Settings.build(max_retries: 1).max_retries)
      assert_equal(0, Settings.build(max_retries: 0).max_retries)
    end

    test "RETRY-12: the key is read ONCE at build; a later configure does not move the snapshot" do
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "7") }
      settings = Settings.build
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "9") }

      assert_equal(7, settings.max_retries)
      assert_equal(9, Settings.build.max_retries)
    end

    test "RETRY-12: with the key unset the default is Policy::DEFAULT_MAX_RETRIES" do
      assert_equal(Policy::DEFAULT_MAX_RETRIES, Settings.build.max_retries)
    end

    test "RETRY-41 / P6-59: a negative CONFIGURED value is clamped to the default and logged" do
      # The one read of the configured key is where RETRY-41's "a negative configured value MUST
      # be clamped to the default (and the clamp logged)" is met, through the same resolver the
      # drivers use; the settings object then holds a valid value (RECOV-34) and every driver
      # built on it sees the default without a second clamp or a second log line.
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "-1") }
      sink = RecordingSink.new
      settings = Settings.build(logger: Dexpace::Instrumentation::Logger.build(sink: sink))

      assert_equal(Policy::DEFAULT_MAX_RETRIES, settings.max_retries)
      assert_equal([:warn], sink.entries.map(&:severity))
      payload = sink.payloads.first

      assert_equal(Dexpace::Instrumentation::Events::INSTRUMENTATION_CONFIG,
                   payload[Dexpace::Instrumentation::Keys::EVENT],)
      assert_match(/-1.*clamped to #{Policy::DEFAULT_MAX_RETRIES}/o,
                   payload[Dexpace::Instrumentation::Keys::MESSAGE],)
      assert_equal(Policy::DEFAULT_MAX_RETRIES, Settings.build.max_retries,
                   "Logger::NULL by default: clamped, reported nowhere",)
    end

    test "RETRY-41 / OBS-20: the clamp's log is contained: a raising sink cannot fail the build" do
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "-3") }
      sink = RecordingSink.new
      sink.define_singleton_method(:warn) { |*| raise ::IOError, "sink write failure" }
      logger = Dexpace::Instrumentation::Logger.build(sink: sink)

      assert_equal(Policy::DEFAULT_MAX_RETRIES, Settings.build(logger: logger).max_retries)
    end

    test "RECOV-34: an EXPLICIT negative max_retries: is still refused, never clamped" do
      # The configured key is the environment's value; an explicit argument is the caller's
      # construction input, and RECOV-34 refuses that at initialize -- with the key negative too.
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "-1") }
      sink = RecordingSink.new
      logger = Dexpace::Instrumentation::Logger.build(sink: sink)

      error = assert_raises(Dexpace::InvalidArgumentError) do
        Settings.build(max_retries: -1, logger: logger)
      end

      assert_includes(error.message, "max_retries")
      assert_empty(sink.entries, "no clamp, so no clamp diagnostic")
    end

    test "P6-59: logger: is read at build and never held -- not a member, absent from #to_h" do
      settings = Settings.build(logger: Dexpace::Instrumentation::Logger::NULL)

      refute_includes(settings.to_h.keys, :logger)
      refute_respond_to(settings, :logger)
      assert_equal(settings, Settings.build, "value equality is over the ten members alone")
    end

    test "RETRY-12 / CFG-5: an unparseable configured value falls to the default (5a's parser)" do
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "seven") }

      assert_equal(Policy::DEFAULT_MAX_RETRIES, Settings.build.max_retries)
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "010") }

      assert_equal(10, Settings.build.max_retries, "base 10 explicit (CFG-5)")
    end

    test "P6-6 / RETRY-14: the configured number is the STAGE vocabulary; attempts are one more" do
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "4") }

      assert_equal(4, Settings.build.max_retries)
      assert_equal(5, Settings.build.max_retries + 1, "the recovery stack's max_attempts")
    end

    test "#with re-validates through .build on every Ruby, never through Data#with" do
      settings = Settings.build(max_retries: 3)
      clock = FakeClock.new

      assert_same(clock, settings.with(clock: clock).clock)
      assert_equal(3, settings.with(clock: clock).max_retries,
                   "an explicit member survives #with",)
      assert_raises(Dexpace::InvalidArgumentError) { settings.with(jitter: 5.0) }
      assert_raises(Dexpace::InvalidArgumentError) { settings.with(initial_delay: -1) }
    end

    test "#with of max_retries never re-hits the configured key" do
      Dexpace.configure { |c| c.env_source = FakeConfigSource.new(KEY => "7") }
      settings = Settings.build(max_retries: 1)

      assert_equal(1, settings.with(jitter: 0.0).max_retries)
    end

    test "RETRY-42: value equality is over the members; two default settings are ==" do
      assert_equal(Settings.build, Settings.build)
      refute_equal(Settings.build, Settings.build(max_retries: 9))
    end
  end
end
