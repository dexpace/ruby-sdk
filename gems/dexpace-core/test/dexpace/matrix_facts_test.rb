# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require "open3"
require "time"
require_relative "../support/fake_clock"
require_relative "../support/fake_config_source"
require_relative "../support/parking_scheduler"

# The six floor-straddling Ruby facts phase 5a's design rests on (its facts 1, 3, 5, 8, 9 and 14),
# asserted on every matrix row rather than remembered from one machine, and the three doubles the
# phase's suites share. CFG-11, CFG-15, CFG-17, CFG-18, CFG-30, CFG-31, CFG-32, CFG-34, CFG-36.
module MatrixFactsTest
  # The six facts.
  class FactsTest < DexpaceTestCase
    # R2 / P5-12: Time.httpdate accepts asctime (no comma anywhere) and RFC 850, and rejects
    # three of CFG-30's four zone tokens -- so neither delegation route satisfies CFG-30 and
    # CFG-31 together.
    test "Fact 1: Time.httpdate accepts asctime and RFC 850, rejects UTC and a missing comma" do
      assert_equal(1994, Time.httpdate("Sun Nov  6 08:49:37 1994").year)
      assert_equal(1994, Time.httpdate("Sunday, 06-Nov-94 08:49:37 GMT").year)
      assert_raises(ArgumentError) { Time.httpdate("Sun, 06 Nov 1994 08:49:37 UTC") }
      assert_raises(ArgumentError) { Time.httpdate("Mon 01 Jan 2024 00:00:00 GMT") }
      assert_equal("Sun, 06 Nov 1994 08:49:37 GMT", Time.utc(1994, 11, 6, 8, 49, 37).httpdate)
    end

    # R3 / P5-13: Fiber[] hands the SAME object to a new thread by identity; Thread.current[] is
    # inherited by neither a child fiber nor a new thread.
    test "Fact 3: Fiber storage leaks an object across threads while Thread.current is isolated" do
      marker = Object.new
      Fiber[:dexpace_fact3] = marker

      assert(Thread.new { Fiber[:dexpace_fact3].equal?(marker) }.value)

      Thread.current[:dexpace_fact3_isolated] = marker

      assert_nil(Thread.new { Thread.current[:dexpace_fact3_isolated] }.value)
      assert_nil(Fiber.new { Thread.current[:dexpace_fact3_isolated] }.resume)
    ensure
      Fiber[:dexpace_fact3] = nil
      Thread.current[:dexpace_fact3_isolated] = nil
    end

    test "Fact 5: Random#bytes returns an unfrozen ASCII-8BIT buffer; Random::DEFAULT is gone" do
      bytes = Random.new.bytes(16)

      refute_predicate(bytes, :frozen?)
      assert_equal(Encoding::ASCII_8BIT, bytes.encoding)
      refute(Random.const_defined?(:DEFAULT))
    end

    # CFG-17's negative guard is 5a's and not the queue's: pop(timeout: -1) returns nil at once and
    # raises nothing, and a closed queue pops nil too -- which is why Clock#sleep's queue is
    # per-call and never closed.
    test "Fact 8: Queue#pop(timeout: -1) returns nil at once; a closed queue pops nil too" do
      queue = Thread::Queue.new
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      assert_nil(queue.pop(timeout: -1))
      assert_operator(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start, :<, 0.05)
      assert_nil(queue.pop(timeout: 0))

      closed = Thread::Queue.new
      closed.close

      assert_nil(closed.pop(timeout: 1))
      assert_equal(1, Process.clock_getres(Process::CLOCK_MONOTONIC, :nanosecond))
    end

    # The scheduler's event loop runs in ParkingScheduler#close, which the interpreter calls when
    # the scheduler's thread ends -- so the suite drives it by joining that thread.
    test "Fact 8: Queue#pop(timeout:) unmounts the fiber under a scheduler, no kernel_sleep" do
      scheduler = ParkingScheduler.new
      popped = :unset
      thread = Thread.new do
        Fiber.set_scheduler(scheduler)
        queue = Thread::Queue.new
        Fiber.schedule { popped = queue.pop(timeout: 0.02) }
      end
      thread.join

      assert_nil(popped)
      assert_equal(1, scheduler.block_count)
      assert_equal(0, scheduler.kernel_sleep_count)
    end

    # R5: CFG-36's three identity components come from constants that need no require and are
    # defined under --disable-gems, where RbConfig is not; the allowlist does not grow.
    test "Fact 9: the RUBY_* constants need no require; RbConfig is absent under --disable-gems" do
      assert_equal("constant", defined?(RUBY_ENGINE))
      assert_equal("constant", defined?(RUBY_ENGINE_VERSION))
      assert_equal("constant", defined?(RUBY_VERSION))
      assert_equal("constant", defined?(RUBY_PLATFORM))
      refute_empty(RUBY_PLATFORM.split("-", 2).last)

      # RUBYOPT is cleared: `bundle exec` exports `-rbundler/setup`, which loads RubyGems -- and
      # RbConfig with it -- into the child before --disable-gems can keep it out.
      out, err, status = Open3.capture3(
        { "RUBYOPT" => nil },
        RbConfig.ruby, "--disable-gems", "-e", "print defined?(RbConfig).inspect",
      )

      assert_predicate(status, :success?, err)
      assert_equal("nil", out)
    end

    test "Fact 14: ENV returns a frozen String per call, and make_shareable(copy: true) copies" do
      ENV["DEXPACE_FACT14"] = "v"
      ENV["DEXPACE_FACT14_EMPTY"] = ""
      begin
        first = ENV.fetch("DEXPACE_FACT14")

        assert_predicate(first, :frozen?)
        refute_same(first, ENV.fetch("DEXPACE_FACT14"))
        assert_equal("", ENV.fetch("DEXPACE_FACT14_EMPTY")) # CFG-2 reads "" versus nil off this
        assert(ENV.key?("DEXPACE_FACT14_EMPTY"))
      ensure
        ENV.delete("DEXPACE_FACT14")
        ENV.delete("DEXPACE_FACT14_EMPTY")
      end

      source = { "a" => ["b"] }
      copy = Ractor.make_shareable(source, copy: true)

      refute_predicate(source, :frozen?)
      assert_predicate(copy, :frozen?)
      refute_same(source, copy)
    end

    # Fact 14's Data#with half is deliberately NOT asserted: it is the one fact whose result differs
    # by interpreter (3.2.11 skips an initialize override, 3.4.10 and 4.0.6 run it), so an assertion
    # either way fails a column. The port's mitigation is phase 1's Model#with, which routes through
    # .build on every version; every 5a Data uses it and never Data#with.
  end

  # The three doubles.
  class DoublesTest < DexpaceTestCase
    test "FakeClock is a _Clock: three operations, advanced by the test, recording its sleeps" do
      clock = FakeClock.new

      assert_kind_of(Time, clock.now)
      assert_kind_of(Float, clock.monotonic)
      own = clock.methods - Object.instance_methods - %i[advance sleeps]

      assert_equal(%i[monotonic now sleep], own.sort)

      clock.advance(5.5)

      assert_in_delta(1005.5, clock.monotonic, 0.001)

      clock.sleep(1.0)

      assert_equal(1, clock.sleeps.size)
      assert_in_delta(1.0, clock.sleeps.first[:duration])
      assert_in_delta(1006.5, clock.monotonic, 0.001)
      assert_raises(Dexpace::InvalidArgumentError) { clock.sleep(-1) }
    end

    test "FakeConfigSource is a _ConfigSource over a test-owned hash" do
      source = FakeConfigSource.new("A" => "alpha")

      assert_equal("alpha", source.call("A"))
      assert_nil(source.call("B"))

      source["B"] = "beta"

      assert_equal("beta", source["B"])
      source["B"] = nil

      assert_nil(source.call("B"))
    end

    # ParkingScheduler's hooks are only ever called BY the interpreter, from inside a non-blocking
    # fiber: #block and #kernel_sleep end in Fiber.yield, and calling either from the root fiber
    # raises FiberError. The scheduler is therefore exercised through Fiber.schedule (the fact-8
    # case above) and never by invoking a hook directly.
    test "ParkingScheduler counts nothing until a scheduled fiber blocks" do
      scheduler = ParkingScheduler.new

      assert_equal(0, scheduler.block_count)
      assert_equal(0, scheduler.kernel_sleep_count)
      assert_equal(0, scheduler.unblock_count)
    end
  end
end
