# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/transport/async_http"
require "openssl"

# Exercises: TRANSPORT-2, TRANSPORT-7, TRANSPORT-8, ASYNC-22 (the async-http facts
# they rest on) -- the phase-8c design's verified facts the adapter's shape depends on, re-run as
# a standing test on every CI row rather than once in a scratch script (8a's precedent). The
# gemspec pins `async-http ~> 0.104`, so what varies across the matrix is the interpreter (3.3,
# 3.4 and 4.0; the 3.2 row has no bundle for this gem, P8-36) and the openssl the bundle
# resolved for it. The first test prints the row's versions so a CI log records which ones each
# row proved. No lib/ mirror: it asserts the library, not a file.
class DexpaceTransportAsyncHTTPMatrixFactsTest < DexpaceTestCase
  test "the active async-http is 0.104 or newer, and the row's versions are printed for the " \
       "record" do
    openssl = Gem.loaded_specs["openssl"]
    protocol = Gem.loaded_specs["protocol-http"]&.version
    puts "\n[phase 8c matrix] ruby #{RUBY_VERSION}: async-http #{::Async::HTTP::VERSION}, " \
         "async #{::Async::VERSION}, protocol-http #{protocol}, openssl #{OpenSSL::VERSION} " \
         "(#{openssl&.default_gem? ? "default gem" : "installed gem"})"

    assert_operator(Gem::Version.new(::Async::HTTP::VERSION), :>=, Gem::Version.new("0.104"))
  end

  test "TRANSPORT-8 / XCUT-2 fact: Async::Cancel is an Exception outside StandardError and " \
       "Async::TimeoutError is a StandardError, so the pair is told apart by class" do
    refute_operator(::Async::Cancel, :<, ::StandardError)
    assert_operator(::Async::Cancel, :<, ::Exception)
    assert_operator(::Async::TimeoutError, :<, ::StandardError)
    assert_same(::Async::Cancel, ::Async::Stop, "Stop is Cancel's older name")
  end

  test "P8-39 fact: outside a reactor there is no current task and no scheduler, which is what " \
       "the adapter's SeamError reads" do
    assert_nil(::Async::Task.current?)
    assert_nil(Fiber.scheduler)
  end

  test "watcher fact: Task#cancel from a foreign OS thread raises rather than cancelling, which " \
       "is why the cancellation crosses threads through a queue and never a cancel" do
    error = nil
    Sync do |task|
      child = task.async { sleep(5) }
      ::Thread.new do
        child.cancel
      rescue ::StandardError => error # the block closes over the outer local
        error
      end.join

      assert_equal(:running, child.status, "the foreign cancel did not land")
      child.cancel
    end

    assert_kind_of(::NoMethodError, error)
  end

  test "watcher fact: Task#cancel(cause:) keeps an Exception cause and replaces anything else " \
       "with the runtime's own, which is why the bridge wraps the reason in CancelledError" do
    seen = cancel_with(cause: ::RuntimeError.new("ours"))

    assert_kind_of(::RuntimeError, seen.cause)
    assert_equal("ours", seen.cause.message)
    assert_kind_of(::Async::Cancel::Cause, cancel_with(cause: :ours).cause)
  end

  test "P8-39 fact: Task#async runs the child eagerly to its first suspension and hands control " \
       "back to the caller's fiber, so a future assigned inside the child is not yet readable" do
    order = []
    Sync do |task|
      child = task.async do
        order << :child_started
        sleep(0.01)
        order << :child_resumed
      end
      order << :caller_continued
      child.wait
    end

    assert_equal(%i[child_started caller_continued child_resumed], order)
  end

  test "ASYNC-22 fact: Fiber.scheduler is one object across every task of one reactor and a " \
       "different one on another thread, which is what keys the client map" do
    inner = nil
    other = nil
    outer = Sync do |task|
      inner = task.async { Fiber.scheduler }.wait
      other = ::Thread.new { Sync { Fiber.scheduler } }.value
      Fiber.scheduler
    end

    assert_same(outer, inner)
    refute_same(outer, other)
    assert_predicate(other, :closed?, "the other thread's reactor closed with its Sync")
  end

  test "TRANSPORT-2 fact: Async::HTTP::Client.new takes retries: and limit:, opens no socket, " \
       "and a caller's ssl_context reaches the endpoint verbatim" do
    context = OpenSSL::SSL::SSLContext.new
    uri = ::URI::RFC3986_PARSER.parse("https://127.0.0.1:1")
    endpoint = ::Async::HTTP::Endpoint.new(uri, ssl_context: context)
    client = ::Async::HTTP::Client.new(endpoint, retries: 0, limit: 3)

    assert_equal(0, client.retries)
    assert_equal(3, client.pool.limit)
    assert_equal(0, client.pool.size)
    assert_same(context, endpoint.ssl_context)
  end

  private

  # The cancellation a child sees under `cancel(cause:)`, as the rescued Async::Cancel.
  def cancel_with(cause:)
    seen = nil
    Sync do |task|
      child = task.async do
        sleep(5)
      rescue ::Exception => error # rubocop:disable Lint/RescueException -- Async::Cancel is an Exception, and the fact under test is what it carries
        seen = error
        raise
      end
      sleep(0.01)
      child.cancel(cause: cause)
      child.wait
    end
    seen
  end
end
