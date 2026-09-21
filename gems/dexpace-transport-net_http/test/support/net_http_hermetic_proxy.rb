# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# An owning adapter resolves its proxy through Dexpace.configuration, whose environment tier is
# the real ENV (CFG-1, CFG-24): on a host that exports HTTPS_PROXY every NetHTTP.build in these
# suites would route its loopback fixture through that proxy, and a NO_PROXY covering a target
# would bypass a fixture that plays the proxy -- review round 1's R1-1, measured at fifteen of
# the adapter suite's thirty-four tests under HTTPS_PROXY=http://127.0.0.1:9. The three keys the
# resolver reads are overridden blank for every test: the override tier sits above the
# environment, and a blank is an answer to Configuration#string that the resolver treats as
# absent (a blank HTTPS_PROXY does not mask HTTP_PROXY, a blank NO_PROXY is no pattern), so
# nothing falls through to ENV and ENV itself is never touched. Dexpace.configure composes over
# the current configuration, so a test that configures a proxy of its own keeps these blanks
# beneath it; every test ends on Configuration::EMPTY. Included by AdapterFixtures and by the
# suites that build an owning adapter without it. Named for its gem: test:gems loads every
# gem's suite into one process.
#
# This module covers the SDK's own chain and nothing else. The library has a second reader of
# the environment, Net::HTTP.new's `:ENV` default, which consults URI#find_proxy on `#start`
# and warns "The environment variable HTTP_PROXY is discouraged" for the upper-case name with no
# lower-case one -- before its loopback exemption, before NO_PROXY, on every row's uri -- and
# the test base makes that warning fatal (review round 2's R2-1). So no fixture in this
# repository ever reaches that default: every raw Net::HTTP a suite starts passes an explicit
# nil proxy (AdapterFixtures#client_for, the conformance driver's borrow factory, the plain
# clients in dexpace-conformance's suites, test/support/net_http_warmup.rb), and the two R17
# controls that reach `:ENV` on purpose set the lower-case name themselves. Together the two
# arrangements make both gems' suites hermetic under HTTP_PROXY, http_proxy, HTTPS_PROXY and
# NO_PROXY alike; adapter_test.rb's "R2-1" case and wire_server_test.rb's PlainClientTest guard
# the fixture half on any host.
module NetHTTPHermeticProxy
  PROXY_KEYS = [
    Dexpace::Configuration::Keys::HTTP_PROXY,
    Dexpace::Configuration::Keys::HTTPS_PROXY,
    Dexpace::Configuration::Keys::NO_PROXY,
  ].freeze

  def setup
    super
    Dexpace.configure { |builder| PROXY_KEYS.each { |key| builder.override(key, "") } }
  end

  def teardown
    Dexpace.reset_config!
    super
  end
end
