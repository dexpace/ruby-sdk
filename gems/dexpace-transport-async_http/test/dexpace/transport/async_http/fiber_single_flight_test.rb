# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/transport/async_http"

# Exercises: XCUT-12 (its fiber-scheduler form), XCUT-11, AUTH-34, AUTH-35, AUTH-37, ASYNC-6.
#
# Phase 10's verification of XCUT-12 under a fiber scheduler, the form phase 9 could not assemble
# (dexpace-conformance declares dexpace-core alone and cannot open a reactor) and routed here.
# Phase 10's design (R9) expected a lock held across a fetch to DEADLOCK two fibers of one thread;
# measured on 3.3.12 and 4.0.6 with async 2.46.0, it does not -- `Thread::Mutex` is per-fiber and
# a second fiber blocking on it parks on the scheduler -- so this is recorded as a verification,
# not a repair (phase 10's P10-21). What a thread-only race CANNOT see, and this can, is a
# single-flight guard keyed by THREAD identity: every fiber of one reactor shares one thread, so
# such a guard lets every fiber fetch. The racers here are fibers of one reactor on one thread,
# asserted rather than assumed, and the provider SUSPENDS inside #fetch -- a Thread::Queue pop,
# which a fiber scheduler routes through the reactor -- so every racer reaches the refresh before
# the one fetch completes. Lives in this gem because it already declares async-http (8a's
# precedent of a driver inside the adapter gem); runs on 3.3+ only (P8-36).
class AsyncHTTPFiberSingleFlightTest < DexpaceTestCase
  RACERS = 8

  # A provider whose #fetch counts itself and suspends until the test releases it.
  class AsyncHTTPParkedProvider
    attr_reader :fetches

    def initialize
      @fetches = 0
      @gate = ::Thread::Queue.new
    end

    def fetch
      @fetches += 1
      @gate.pop
      Dexpace::Auth::BearerToken.build(token: "t#{@fetches}", expiry: ::Time.now + 3600)
    end

    # One pass for every racer, so a guard that let every fiber fetch fails the count rather than
    # parking the reactor forever.
    def release = RACERS.times { @gate << true }
  end

  def request
    Dexpace::Request.build(method: "GET", url: "https://example.test/", headers: Dexpace::Headers::EMPTY)
  end

  # Starts RACERS fibers under one reactor, each recording its thread and calling `stamp`, lets
  # every one run to its suspension point, then releases the provider.
  def race(provider, &stamp)
    threads = []
    stamped = []
    Sync do |task|
      fibers = Array.new(RACERS) do
        task.async do
          threads << ::Thread.current
          stamped << yield(request)
        end
      end
      task.yield until threads.size == RACERS
      provider.release
      fibers.each(&:wait)
    end
    [threads, stamped]
  end

  test "XCUT-12, AUTH-34: BearerStamper refreshes once for every fiber of one reactor" do
    provider = AsyncHTTPParkedProvider.new
    stamper = Dexpace::Auth::BearerStamper.new(provider: provider)

    threads, stamped = race(provider) { |req| stamper.call(req) }

    assert_equal(1, threads.uniq.size, "the racers were fibers of one thread")
    assert_equal(1, provider.fetches, "a refresh under one reactor was not single-flight")
    assert_equal(["Bearer t1"], stamped.map { |r| r.headers["Authorization"] }.flatten.uniq)
  end

  test "XCUT-12, AUTH-37: AsyncBearerStamper coalesces every fiber onto one fetch" do
    provider = AsyncHTTPParkedProvider.new
    stamper = Dexpace::Auth::AsyncBearerStamper.new(provider: provider)

    threads, stamped = race(provider) { |req| stamper.stamp(req).value }

    assert_equal(1, threads.uniq.size, "the racers were fibers of one thread")
    assert_equal(1, provider.fetches, "the async stamper fetched more than once")
    assert_equal(RACERS, stamped.size)
  end

  # AUTH-35 under the same reactor: a provider result the stamper rejects is not cached, so the
  # next fiber fetches again -- single-flight must not mean "a failure is shared forever".
  test "AUTH-35: a rejected fetch caches nothing, and the next fiber fetches afresh" do
    results = [nil, Dexpace::Auth::BearerToken.build(token: "ok", expiry: ::Time.now + 3600)]
    provider = Object.new
    provider.define_singleton_method(:fetch) { results.shift }
    stamper = Dexpace::Auth::BearerStamper.new(provider: provider)

    Sync do
      assert_raises(Dexpace::Auth::ProviderError) { stamper.call(request) }
      assert_equal(["Bearer ok"], stamper.call(request).headers["Authorization"])
    end
  end
end
