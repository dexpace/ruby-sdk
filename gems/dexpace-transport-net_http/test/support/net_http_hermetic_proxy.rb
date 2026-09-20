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
