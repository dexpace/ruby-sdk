# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"

# NFR-15: the version a published artifact reports at runtime is the real one. Styleguide 12.7:
# no constant outside Dexpace::.
class ConformanceTest < DexpaceTestCase
  # The top-level namespace is snapshotted around the require, so "defines nothing outside
  # Dexpace" holds whether this file loads alone or after the other five gems in one
  # `rake test:gems` process, where Dexpace already exists. `socket` -- the one stdlib feature this
  # gem's lib/ requires beyond core's own, for the wire server, and permitted to this gem alone by
  # the allowlist's scoped denial (P8-14) -- and `tempfile` (TRANSPORT-28) are loaded first, the
  # way core's smoke suite preloads `digest`: the ten top-level constants `socket` defines
  # (Addrinfo, BasicSocket, IPSocket, Socket, SocketError, TCPServer, TCPSocket, UDPSocket,
  # UNIXServer, UNIXSocket -- measured identically on 3.2.11, 3.3.12, 3.4.10 and 4.0.6) and
  # Tempfile are theirs, not the entry file's; and so is core's whole tree, which the entry file
  # requires as a consumer would.
  require "socket"
  require "tempfile"
  require "dexpace"
  TOP_LEVEL_BEFORE = Object.constants
  NAMESPACE_BEFORE = defined?(Dexpace) ? Dexpace.constants(false) : []
  require "dexpace/conformance"
  TOP_LEVEL_ADDED = (Object.constants - TOP_LEVEL_BEFORE).freeze
  NAMESPACE_ADDED = (Dexpace.constants(false) - NAMESPACE_BEFORE).freeze
  # Captured at load, before any test runs: rspec_driver_test.rb requires the RSpec driver inside
  # its own test bodies, so a read at test time would depend on the random order.
  ENTRY_FILE_DEFINES = Dexpace::Conformance.constants(false).sort.freeze

  # The public surface phase 8a built into the skeleton (design, "The object model 8a ships"),
  # exactly: the five protocol types, the fixture and its scripts, the case, the suite, the
  # Minitest driver, the two observability doubles and the borrowed pair. RSpecDriver is defined
  # by a file the entry point deliberately does NOT require (an RSpec-only consumer opts in), so
  # it is absent here and its own test loads it.
  PUBLIC = %i[
    VERSION Failure Vacuous Assertion Result Report Scripts WireServer BorrowedPair TransportCase
    TransportSuite MinitestDriver RecordingSpan Allocations
  ].freeze

  test "defines a semver VERSION string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::Conformance::VERSION)
  end

  test "the VERSION matches the gemspec this gem is built from" do
    gemspec = File.expand_path("../../dexpace-conformance.gemspec", __dir__)
    spec = Gem::Specification.load(gemspec)

    assert_equal(spec.version.to_s, Dexpace::Conformance::VERSION)
  end

  test "defines nothing outside the Dexpace namespace, and exactly its own constants inside it" do
    assert_empty(TOP_LEVEL_ADDED - [:Dexpace], "top-level constants added by the entry file")
    assert_empty(NAMESPACE_ADDED - %i[Conformance], "constants added directly under Dexpace")
    assert_equal(PUBLIC.sort, ENTRY_FILE_DEFINES)
  end

  test "declares dexpace-core and nothing else, by design" do
    gemspec = File.expand_path("../../dexpace-conformance.gemspec", __dir__)
    spec = Gem::Specification.load(gemspec)

    assert_equal(["dexpace-core"], spec.runtime_dependencies.map(&:name))
  end
end
