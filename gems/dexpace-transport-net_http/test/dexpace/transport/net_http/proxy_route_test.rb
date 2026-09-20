# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/adapter_fixtures"
require_relative "../../../support/net_http_recording_sink"
require "dexpace/transport/net_http"

# TRANSPORT-30, including both of its embedded MUSTs, consuming CFG-22 to CFG-28 (8a's R17):
# phase 5a's resolver meets its first consumer here. Every configuration handed to the route is a
# hermetic from_hash source, never the process environment, because Configuration::EMPTY reads the
# real ENV; the one test that drives the whole adapter sets the process-wide slot through
# Dexpace.configure's override tier, which sits above the environment, and resets it in an ensure.
# ProxyRoute is a private_constant, reached through const_get.
class DexpaceTransportNetHttpProxyRouteTest < DexpaceTestCase
  include AdapterFixtures

  NetHTTP = Dexpace::Transport::NetHTTP
  ProxyRoute = NetHTTP.const_get(:ProxyRoute)
  Keys = Dexpace::Configuration::Keys

  def url(host = "api.example.com")
    Dexpace::URL.parse!("https://#{host}/v1/pets")
  end

  def configuration_with(pairs)
    Dexpace::Configuration.build(env_source: Dexpace::Configuration::Sources.from_hash(pairs))
  end

  def logger_over(sink)
    Dexpace::Instrumentation::Logger.build(sink: sink)
  end

  test "is a private_constant of NetHTTP" do
    assert_raises(NameError) { NetHTTP::ProxyRoute }
  end

  test "no configured proxy yields four nils, so Net::HTTP gets an explicit nil p_addr" do
    route = ProxyRoute.for(url, configuration: configuration_with({}))

    assert_nil(route.address)
    assert_nil(route.port)
    assert_nil(route.username)
    assert_nil(route.password)
    assert_equal(ProxyRoute.none, route)
  end

  test "a resolved proxy's four values reach the route" do
    configuration = configuration_with(Keys::HTTPS_PROXY => "http://u:pw@proxy.example:3128")

    route = ProxyRoute.for(url, configuration: configuration)

    assert_equal("proxy.example", route.address)
    assert_equal(3128, route.port)
    assert_equal("u", route.username)
    assert_equal("pw", route.password)
  end

  # CFG-23: the bypass decision is the resolved Proxy's, asked per target host.
  test "a host matching the non-proxy list is routed directly; another host is not" do
    configuration = configuration_with(Keys::HTTPS_PROXY => "http://proxy.example:3128",
                                       Keys::NO_PROXY => "*.example.com",)

    assert_nil(ProxyRoute.for(url("api.example.com"), configuration: configuration).address)
    assert_equal("proxy.example",
                 ProxyRoute.for(url("other.test"), configuration: configuration).address,)
  end

  # TRANSPORT-30's SHOULD, in the one shape Net::HTTP makes reachable.
  test "a proxy carrying a challenge handler warns once and still routes through Basic" do
    sink = NetHTTPRecordingSink.new
    configuration = configuration_with(Keys::HTTPS_PROXY => "http://u:pw@proxy.example:3128")
    proxy = Dexpace::Proxy.resolve(configuration).with(challenge_handler: ->(_challenge) {})

    route = ProxyRoute.from(proxy, url, logger: logger_over(sink))

    assert_equal("proxy.example", route.address)
    assert_equal("u", route.username)
    warnings = sink.events(NetHTTP::PROXY_LIMITATION_EVENT)

    assert_equal(1, warnings.size)
    assert_equal(:warn, warnings.first.severity)
    assert_match(/challenge handler/, warnings.first.payload["unhonoured"])
    assert_match(/Basic/, warnings.first.payload["remedy"])
  end

  test "a SOCKS proxy takes the same warning, naming the type, and still routes" do
    sink = NetHTTPRecordingSink.new
    proxy = Dexpace::Proxy.build(type: :socks5, host: "socks.example", port: 1080)

    route = ProxyRoute.from(proxy, url, logger: logger_over(sink))

    assert_equal("socks.example", route.address)
    assert_match(/proxy type/, sink.events(NetHTTP::PROXY_LIMITATION_EVENT).first.payload["unhonoured"])
  end

  test "a plain HTTP proxy with no handler warns about nothing" do
    sink = NetHTTPRecordingSink.new
    configuration = configuration_with(Keys::HTTPS_PROXY => "http://proxy.example:3128")

    ProxyRoute.for(url, configuration: configuration, logger: logger_over(sink))

    assert_empty(sink.entries)
  end

  # TRANSPORT-30's first embedded MUST: "Proxy credentials MUST NOT be logged."
  test "no log event anywhere in a proxied exchange carries the credential" do
    sink = NetHTTPRecordingSink.new
    configuration = configuration_with(Keys::HTTPS_PROXY => "http://u:s3cret@proxy.example:3128")
    proxy = Dexpace::Proxy.resolve(configuration, logger: logger_over(sink))
      .with(challenge_handler: ->(_challenge) {})

    ProxyRoute.from(proxy, url, logger: logger_over(sink))

    refute_empty(sink.entries, "the limitation warning was emitted")
    refute_match(/s3cret/, sink.entries.inspect)
  end

  # TRANSPORT-30's second embedded MUST: "MUST NOT be answered to an origin-server (401)
  # challenge." With a credentialled proxy CONFIGURED through the chain -- the fixture plays the
  # proxy, on the adapter suite's ProxyTest precedent -- the one request that reaches it carries
  # the preemptive Basic the SHOULD's fallback stamps, and the 401 it answers draws no second
  # request: this adapter stamps no header in response to any status, because it never reads one.
  # With no proxy configured there was no credential to leak and the assertion held against any
  # adapter (review round 0's R0-9); the target is TEST-NET-1 because find_proxy exempts loopback.
  test "an origin 401 draws no second, Proxy-Authorization-bearing request out of the adapter" do
    proxy = wire(Dexpace::Conformance::Scripts.vendor_status(401, "denied"))
    target = Dexpace::Request.build(method: "GET", url: "http://192.0.2.1/private",
                                    headers: Dexpace::Headers::EMPTY, body: nil,)
    Dexpace.configure do |builder|
      builder.override(Keys::HTTP_PROXY, "http://u:pw@127.0.0.1:#{proxy.port}")
    end

    response = settle(NetHTTP.build, target)

    assert_equal(401, response.status.code)
    assert_equal(1, proxy.requests.size, "no second, credential-carrying request")
    assert_equal("Basic #{["u:pw"].pack("m0")}", proxy.requests.first.header("proxy-authorization"),
                 "the Basic fallback goes out preemptively, once, with the first request",)
    assert_equal("GET http://192.0.2.1/private HTTP/1.1", proxy.requests.first.request_line)
    response.close
  ensure
    Dexpace.reset_config!
  end
end
