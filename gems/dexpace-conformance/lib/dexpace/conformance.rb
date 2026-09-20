# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The whole of dexpace-core: this gem declares it and reaches every Dexpace:: constant its
# assertions name through the one entry point, exactly as a consumer of the suite would.
require "dexpace"
require_relative "conformance/version"
# The assertion protocol's five value types (design §9.3, 8a's R7), in dependency-free order.
require_relative "conformance/failure"
require_relative "conformance/vacuous"
require_relative "conformance/assertion"
require_relative "conformance/result"
require_relative "conformance/report"
# The TCPServer fixture and its named scripts (design §9.3; `socket` is permitted to this gem
# alone by the require allowlist's scoped denial, P8-14).
require_relative "conformance/scripts"
require_relative "conformance/wire_server"
# The case an assertion receives, the borrowed pair, and the runner (8a's R16 suite contract).
require_relative "conformance/borrowed_pair"
require_relative "conformance/transport_case"
require_relative "conformance/transport_suite"
# The Minitest driver, and deliberately NOT the RSpec one: an RSpec-only consumer requires
# "dexpace/conformance/rspec_driver" itself, so a Minitest-only consumer never loads a file naming
# the other framework (design §9.3). Neither requires its framework.
require_relative "conformance/minitest_driver"
# The two observability doubles phases 5c and 5b assigned to this gem (OBS-21, OBS-25).
require_relative "conformance/recording_span"
require_relative "conformance/allocations"

module Dexpace
  # The conformance suite every adapter is proven against (design §9.3): the assertion protocol
  # phase 0 postponed to phase 8a -- Failure, Vacuous, Assertion, Result and Report -- with the
  # transport suite, its TCPServer fixture and the two thin drivers landing beside them; phase 9
  # adds the remaining suites. Declares dexpace-core and nothing else, by design: neither driver
  # requires its framework, so Minitest is never a runtime constraint on a consumer.
  module Conformance
  end
end
