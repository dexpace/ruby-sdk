# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/adapter_fixtures"
require "dexpace/transport/net_http"
require "openssl"

# 8a's R18: `.build`'s `tls:` keyword. No TRANSPORT ID -- this is public surface NFR-4 locks, and
# the values are plain so no OpenSSL constant reaches a public signature (NFR-11). The plaintext
# fixture (P8-9) is why the last test is structural rather than a handshake. TLSSettings is a
# private_constant, reached through const_get.
class DexpaceTransportNetHttpTLSSettingsTest < DexpaceTestCase
  include AdapterFixtures

  NetHTTP = Dexpace::Transport::NetHTTP
  TLSSettings = NetHTTP.const_get(:TLSSettings)

  test "is a private_constant of NetHTTP, and TLS_SETTINGS is the frozen six-key set" do
    assert_raises(NameError) { NetHTTP::TLSSettings }
    assert_equal(%i[ca_file ca_path cert key verify_mode min_version], NetHTTP::TLS_SETTINGS)
    assert_predicate(NetHTTP::TLS_SETTINGS, :frozen?)
  end

  test "the default assigns nothing, so SSLContext#set_params supplies VERIFY_PEER" do
    http = ::Net::HTTP.new("example.com", 443)
    TLSSettings.apply(http, TLSSettings.validate!(nil))

    assert_nil(http.verify_mode, "an unassigned verify_mode is what lets set_params default it")
    assert_nil(http.ca_file)
    assert_nil(http.min_version)
    assert_equal(OpenSSL::SSL::VERIFY_PEER, OpenSSL::SSL::SSLContext.new.tap do |c|
      c.set_params({})
    end.verify_mode,)
  end

  test "each accepted key reaches the client, and the validated hash is frozen" do
    http = ::Net::HTTP.new("example.com", 443)
    settings = TLSSettings.validate!(ca_file: "/tmp/ca.pem", ca_path: "/tmp/certs",
                                     verify_mode: OpenSSL::SSL::VERIFY_PEER, min_version: :TLS1_2,)
    TLSSettings.apply(http, settings)

    assert_predicate(settings, :frozen?)
    assert_equal("/tmp/ca.pem", http.ca_file)
    assert_equal("/tmp/certs", http.ca_path)
    assert_equal(OpenSSL::SSL::VERIFY_PEER, http.verify_mode)
    assert_equal(:TLS1_2, http.min_version)
  end

  test "an unknown key raises and names itself and the accepted set" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      TLSSettings.validate!(verify_hostname: false)
    end

    assert_match(/verify_hostname/, error.message)
    assert_match(/ca_file/, error.message)
  end

  test "a non-Hash tls: raises rather than being coerced" do
    error = assert_raises(Dexpace::InvalidArgumentError) { TLSSettings.validate!("/tmp/ca.pem") }

    assert_match(/String/, error.message)
    assert_raises(Dexpace::InvalidArgumentError) { NetHTTP.build(tls: [:ca_file]) }
  end

  test ".build validates tls: at construction, before any call" do
    error = assert_raises(Dexpace::InvalidArgumentError) { NetHTTP.build(tls: { bogus: 1 }) }

    assert_match(/bogus/, error.message)
  end

  # The assertion is that a plain-http URL never reaches #apply at all: a bogus ca_file would
  # have failed a handshake, and the plaintext call succeeds.
  test "tls: is not applied to a plain-http request" do
    server = wire(Dexpace::Conformance::Scripts.fixed("ok"))
    adapter = NetHTTP.build(tls: { ca_file: "/nonexistent/ca.pem",
                                   verify_mode: OpenSSL::SSL::VERIFY_PEER, })

    response = settle(adapter, request_for(server))

    assert_equal("ok", response.body_string)
  end
end
