# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "open3"
require "rbconfig"
require_relative "../../test_helper"

# NFR-15: the version a published artifact reports at runtime is the real one. Styleguide 12.7:
# no constant outside Dexpace::.
class NetHTTPTest < DexpaceTestCase
  # The top-level namespace is snapshotted around the require, so "defines nothing outside
  # Dexpace" holds whether this file loads alone or after the other five gems in one
  # `rake test:gems` process, where Dexpace already exists. `net/http` -- the one library this
  # gem's lib/ requires beyond core's own, declared in the gemspec -- and `dexpace` itself are
  # loaded first, the way core's smoke suite preloads `digest`: `Net` and core's whole tree are
  # theirs, not the entry file's. The intermediate namespace is snapshotted the same way: a
  # sibling this entry file placed beside its own constant -- `Dexpace::Transport::Shared` --
  # is outside the gem's namespace and inside nothing this suite would otherwise look at.
  require "net/http"
  require "dexpace"
  TOP_LEVEL_BEFORE = Object.constants
  NAMESPACE_BEFORE = defined?(Dexpace) ? Dexpace.constants(false) : []
  SIBLINGS_BEFORE = defined?(Dexpace::Transport) ? Dexpace::Transport.constants(false) : []
  require "dexpace/transport/net_http"
  TOP_LEVEL_ADDED = (Object.constants - TOP_LEVEL_BEFORE).freeze
  NAMESPACE_ADDED = (Dexpace.constants(false) - NAMESPACE_BEFORE).freeze
  SIBLINGS_ADDED = (Dexpace::Transport.constants(false) - SIBLINGS_BEFORE).freeze

  # The public surface phase 8a built into the skeleton (design, "The object model 8a ships"):
  # the transport, the eight named constants and phase 0's VERSION. The seven private_constants
  # are absent from constants(false) by definition.
  PUBLIC = %i[
    VERSION Adapter DEFAULT_TIMEOUT_SECONDS MIN_TIMEOUT_SECONDS JOIN_DEADLINE_SECONDS REGISTRY_KEY
    TLS_SETTINGS MANAGED_HEADERS DEFAULT_CONTENT_TYPE PROXY_LIMITATION_EVENT
  ].freeze

  test "defines a semver VERSION string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::Transport::NetHTTP::VERSION)
  end

  test "the VERSION matches the gemspec this gem is built from" do
    gemspec = File.expand_path("../../../dexpace-transport-net_http.gemspec", __dir__)
    spec = Gem::Specification.load(gemspec)

    assert_equal(spec.version.to_s, Dexpace::Transport::NetHTTP::VERSION)
  end

  test "defines nothing outside the Dexpace namespace, and exactly its own constants inside it" do
    assert_empty(TOP_LEVEL_ADDED - [:Dexpace], "top-level constants added by the entry file")
    assert_empty(NAMESPACE_ADDED - %i[Transport], "constants added directly under Dexpace")
    assert_empty(SIBLINGS_ADDED - %i[NetHTTP], "constants added beside this gem's namespace")
    assert_equal(PUBLIC.sort, Dexpace::Transport::NetHTTP.constants(false).sort)
  end

  # The registration is proved in a bare subprocess, where nothing else has required the gem:
  # in one `rake test:gems` process the adapter's own suites load first and the key is already
  # there, so an in-process before/after snapshot would prove nothing.
  test "registers itself under REGISTRY_KEY at require time; the registry resolves an adapter" do
    assert_includes(Dexpace::Transport.registered_keys, Dexpace::Transport::NetHTTP::REGISTRY_KEY)
    assert_kind_of(Dexpace::Transport::NetHTTP::Adapter, Dexpace::Transport.resolve)
    assert_equal("[:net_http]", bare_require("p Dexpace::Transport.registered_keys").strip)
  end

  test "declares dexpace-core and net-http, and nothing else (NFR-2)" do
    gemspec = File.expand_path("../../../dexpace-transport-net_http.gemspec", __dir__)
    spec = Gem::Specification.load(gemspec)

    assert_equal(%w[dexpace-core net-http], spec.runtime_dependencies.map(&:name).sort)
    assert_equal([">= 0.4"], spec.runtime_dependencies.find do |d|
      d.name == "net-http"
    end.requirement.as_list,)
  end

  LIBS = [File.expand_path("../../../lib", __dir__),
          File.expand_path("../../../../dexpace-core/lib", __dir__),].freeze
  private_constant :LIBS

  private

  def bare_require(program)
    command = [RbConfig.ruby, "-w", "-W:deprecated", *LIBS.flat_map { |lib| ["-I", lib] }, "-e",
               "require \"dexpace/transport/net_http\"; #{program}",]
    stdout, stderr, status = Open3.capture3({ "RUBYOPT" => nil }, *command)

    assert_predicate(status, :success?, stderr)
    assert_empty(stderr, "a bare require must be silent under -w")
    stdout
  end
end
