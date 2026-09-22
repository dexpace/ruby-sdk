# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# A configuration chain that reads nothing off the host: `Dexpace::Configuration.build` defaults
# `env_source:` to `Sources::ENVIRONMENT`, the real process environment, so a test that asserts a
# DEFAULT through it -- the connection limit's 8, the timeout's 60 seconds -- would move under a
# developer's exported `TRANSPORT_CONNECTION_LIMIT` or `REQUEST_TIMEOUT` (review round 0's R0-1,
# measured moving under both). Every adapter test that asserts a value the chain resolves builds
# its configuration here, with the environment tier answering nothing, so the only tiers left are
# the overrides the test itself wrote and the default. Named for its gem (phase 8a's rule 35):
# `test:gems` loads every gem's test/support/ into one process.
module AsyncHTTPHermeticConfiguration
  # @param overrides [Hash] the exact-name override map, the one tier above the default
  # @return [Dexpace::Configuration]
  def hermetic_configuration(overrides = {})
    Dexpace::Configuration.build(overrides: overrides,
                                 env_source: Dexpace::Configuration::Sources::NONE,)
  end
end
