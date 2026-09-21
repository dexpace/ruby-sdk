# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/transport/async_http"

# Dispatch step 9: Dexpace::Request#url arrives already parsed by URI::RFC3986_PARSER (phase 1's
# Dexpace::URL.parse!), and this module hands that object to Async::HTTP::Endpoint.new -- never
# to Endpoint.parse, which routes through URI::DEFAULT_PARSER (design §3.5, boundary 19). The
# TLS defaults are the design's: VERIFY_PEER for every host and ALPN offering h2, because
# async-http's own context leaves `localhost` unverified and a caller-supplied context gets no
# ALPN (the design's verified fact 3, re-measured on 0.105.0).
class DexpaceTransportAsyncHTTPEndpointsTest < DexpaceTestCase
  Endpoints = Dexpace::Transport::AsyncHTTP.const_get(:Endpoints, false)

  def url(string) = Dexpace::URL.parse!(string)

  test "builds a plaintext endpoint straight from the already-parsed URI" do
    endpoint = Endpoints.for(url("http://example.test:8080/a%20b?q=1"))

    assert_equal("example.test", endpoint.url.host)
    assert_equal(8080, endpoint.url.port)
    assert_equal("/a%20b?q=1", endpoint.path)
    assert_nil(endpoint.instance_variable_get(:@options)[:ssl_context])
  end

  test "an https URL always gets an adapter-supplied ssl_context that verifies the peer" do
    endpoint = Endpoints.for(url("https://localhost/"))

    assert_equal(::OpenSSL::SSL::VERIFY_PEER, endpoint.ssl_context.verify_mode)
  end

  test "the adapter-supplied ssl_context offers h2 and http/1.1 by ALPN" do
    endpoint = Endpoints.for(url("https://example.test/"))

    assert_equal(%w[h2 http/1.1], endpoint.ssl_context.alpn_protocols)
    assert_equal(Dexpace::Transport::AsyncHTTP::ALPN_PROTOCOLS, endpoint.ssl_context.alpn_protocols)
  end

  test "a caller-supplied ssl_context is used verbatim and not silently re-armed" do
    context = ::OpenSSL::SSL::SSLContext.new
    endpoint = Endpoints.for(url("https://example.test/"), ssl_context: context)

    assert_same(context, endpoint.ssl_context)
    assert_nil(endpoint.ssl_context.alpn_protocols, "verbatim means no ALPN was added either")
  end

  # Dexpace::URL.parse! admits ftp:// and Endpoint.new would dial port 21: the screen is the
  # adapter's (TRANSPORT-21's "a URL the endpoint cannot build" delivered through the future).
  test "a scheme other than http or https is refused as InvalidArgumentError, not dialled" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Endpoints.for(url("ftp://example.test/")) }

    assert_match(/http and https only/, error.message)
    assert_match(/TRANSPORT-21/, error.message)
  end

  test "the origin key is scheme, host and port, folded, and two URLs on one origin share it" do
    a = Endpoints.origin_for(url("https://Example.test:443/one"))
    b = Endpoints.origin_for(url("https://example.test/two"))
    c = Endpoints.origin_for(url("https://example.test:8443/one"))

    assert_equal(a, b)
    assert_equal(["https", "example.test", 443], a)
    refute_equal(a, c)
    assert_predicate(a, :frozen?)
  end

  # Boundary 19, asserted over the source: the documented entry point is the wrong one here.
  test "never calls Endpoint.parse or URI.parse anywhere under lib/" do
    sources = Dir.glob(File.expand_path("../../../../lib/**/*.rb", __dir__))
      .map { |path| File.read(path).gsub(/^\s*#.*$/, "") }.join

    refute_match(/Endpoint\.parse|URI\.parse\b|DEFAULT_PARSER/, sources)
  end
end
