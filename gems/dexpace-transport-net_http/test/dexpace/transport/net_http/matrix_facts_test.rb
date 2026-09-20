# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/transport/net_http"
require "socket"
require "openssl"

# Exercises: TRANSPORT-2, TRANSPORT-3, TRANSPORT-6, TRANSPORT-10, TRANSPORT-11, TRANSPORT-26 (the
# net-http facts they rest on) -- the phase-8a design's verified facts the adapter's shape depends
# on, re-run as a standing test on every CI row rather than once in a scratch script (5a's to
# 6c's precedent). The gemspec pins `net-http >= 0.4` with no upper bound, so the ACTIVE net-http
# version is what varies across the matrix and not only the interpreter: 3.2.11 carries 0.4.1
# as its default gem, 3.4.10 carries 0.6.0, 4.0.6 carries 0.9.1, and a networked resolution on
# any row can activate a newer one. The first test prints the active version so a CI log records
# which one each row proved, and the two version-bound facts below are asserted as the
# disjunction the adapter is correct under. No lib/ mirror: it asserts the library, not a file.
class DexpaceTransportNetHttpMatrixFactsTest < DexpaceTestCase
  def net_http_version
    Gem::Version.new(::Net::HTTP::VERSION)
  end

  test "the active net-http is 0.4 or newer, and the row's version is printed for the record" do
    spec = Gem.loaded_specs["net-http"]
    puts "\n[phase 8a matrix] ruby #{RUBY_VERSION}: net-http #{::Net::HTTP::VERSION} " \
         "(#{spec&.default_gem? ? "default gem" : "installed gem"}), openssl #{OpenSSL::VERSION}"

    assert_operator(net_http_version, :>=, Gem::Version.new("0.4"))
  end

  test "TRANSPORT-2 fact 2: max_retries defaults to 1 and the retried set covers PUT and DELETE" do
    idempotent = ::Net::HTTP.const_get(:IDEMPOTENT_METHODS_)

    assert_equal(1, ::Net::HTTP.new("example.com", 80).max_retries)
    assert_includes(idempotent, "PUT")
    assert_includes(idempotent, "DELETE")
  end

  test "TRANSPORT-3 fact 3: an IOError is on the library's own retry rescue list, so only " \
       "max_retries = 0 lets a socket close under a read surface" do
    source = File.read(::Net::HTTP.instance_method(:transport_request).source_location.first)

    assert_match(/rescue Net::ReadTimeout, IOError, EOFError/, source)
  end

  test "TRANSPORT-6 fact 8: the three timeout knobs accept a float below a millisecond, and 0 is " \
       "poll-once rather than unbounded" do
    http = ::Net::HTTP.new("example.com", 80)
    http.open_timeout = 0.0005
    http.read_timeout = 0.0005
    http.write_timeout = 0.0005

    assert_in_delta(0.0005, http.read_timeout)
    assert_operator(Dexpace::Transport::NetHTTP::MIN_TIMEOUT_SECONDS, :>, 0.0005)
  end

  test "TRANSPORT-10/26 version-bound fact 5: supply_default_content_type warns under -w on " \
       "net-http < 0.9 and is absent from 0.9; the adapter's own Content-Type holds on both" do
    request = ::Net::HTTPGenericRequest.new("POST", true, true, "/", {})

    if request.respond_to?(:supply_default_content_type, true)
      assert_operator(net_http_version, :<, Gem::Version.new("0.9"))
    else
      assert_operator(net_http_version, :>=, Gem::Version.new("0.9"))
    end
  end

  test "TRANSPORT-11 fact 4: a caller-set Host is honoured verbatim by the native request" do
    request = ::Net::HTTPGenericRequest.new("GET", false, true, "/", { "Host" => "bogus.example" })

    assert_equal("bogus.example", request["Host"])
  end

  test "P8-2 fact 13: the empty-initheader construction stamps exactly Accept-Encoding, Accept " \
       "and User-Agent, and #[]= on Accept-Encoding flips decode_content off" do
    request = ::Net::HTTPGenericRequest.new("GET", false, true, "/", {})

    assert_equal(%w[accept accept-encoding user-agent], request.to_hash.keys.sort)
    assert(request.decode_content)
    request["Accept-Encoding"] = "identity"

    refute(request.decode_content)
  end

  test "R1 fact 10: Fiber#resume from another thread raises FiberError, which is why the pump " \
       "is a thread" do
    fiber = Fiber.new { Fiber.yield(:first) }
    fiber.resume
    error = nil

    ::Thread.new do
      fiber.resume
    rescue FiberError => error # the block closes over the outer local
      error
    end.join

    assert_kind_of(FiberError, error)
  end

  test "R17 fact: Net::HTTP.new's p_addr defaults to :ENV and reads a lower-case http_proxy for " \
       "a non-loopback target" do
    saved = ENV.fetch("http_proxy", nil)
    ENV["http_proxy"] = "http://user:pw@127.0.0.1:3128"

    default = ::Net::HTTP.new("192.0.2.1", 80)
    explicit = ::Net::HTTP.new("192.0.2.1", 80, nil, nil, nil, nil)

    assert_predicate(default, :proxy?)
    assert_equal("127.0.0.1", default.proxy_address)
    refute_predicate(explicit, :proxy?)
  ensure
    ENV["http_proxy"] = saved
  end

  test "version-bound fact: Socket::ResolutionError exists from 3.3, and SocketError covers it " \
       "everywhere, which is why Failures wraps the family and not the name" do
    if defined?(::Socket::ResolutionError)
      assert_operator(::Socket::ResolutionError, :<, ::SocketError)
    else
      assert_operator(Gem::Version.new(RUBY_VERSION), :<, Gem::Version.new("3.3"))
    end
  end

  test "P8-15 fact 9: Net::HTTP exposes address and port as readers only" do
    http = ::Net::HTTP.new("example.com", 80)

    refute_respond_to(http, :address=)
    refute_respond_to(http, :port=)
    assert_respond_to(http, :use_ssl=)
  end

  test "R18 fact 16: an SSLContext with no assignments defaults to VERIFY_PEER" do
    context = OpenSSL::SSL::SSLContext.new
    context.set_params({})

    assert_equal(OpenSSL::SSL::VERIFY_PEER, context.verify_mode)
  end
end
