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
# The requirement-level map a Report reads to tell a MUST-level vacuity from a SHOULD-level one
# (phase 9, design R3); generated from appendix C by tools/requirement_levels.rb.
require_relative "conformance/levels"
require_relative "conformance/report"
# Phase 9's shared instrument: the one assertion primitive, the one status loop and XCUT-11's
# structural predicate, then the four suites it carries and the one aggregate over them.
require_relative "conformance/check"
require_relative "conformance/runner"
require_relative "conformance/shared_instance"
require_relative "conformance/invariant_case"
require_relative "conformance/invariant_suite"
require_relative "conformance/packaging_case"
require_relative "conformance/packaging_suite"
require_relative "conformance/codec_case"
require_relative "conformance/codec_suite"
require_relative "conformance/executor_case"
require_relative "conformance/executor_suite"
require_relative "conformance/aggregate"
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
