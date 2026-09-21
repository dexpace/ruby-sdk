# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "open3"
require "prism"
require "rbconfig"
require_relative "../../test_helper"

# NFR-15: the version a published artifact reports at runtime is the real one. Styleguide 12.7:
# no constant outside Dexpace::. NFR-2: dexpace-core plus async-http and nothing else. P8-36: this
# gem's own Ruby floor. SEAM-5/SEAM-6: the require-time registration, proved in a bare child.
class AsyncHTTPTest < DexpaceTestCase
  # The top-level namespace is snapshotted around the require, so "defines nothing outside
  # Dexpace" holds whether this file loads alone or after the other five gems in one
  # `rake test:gems` process, where Dexpace already exists. `async/http` -- the one library this
  # gem's lib/ requires beyond core's own, declared in the gemspec -- and `dexpace` itself are
  # loaded first, the way core's smoke suite preloads `digest`: `Async`, `Protocol`, `Console`,
  # `IO::Endpoint` and core's whole tree are theirs, not the entry file's.
  require "async/http"
  require "dexpace"
  TOP_LEVEL_BEFORE = Object.constants
  NAMESPACE_BEFORE = defined?(Dexpace) ? Dexpace.constants(false) : []
  SIBLINGS_BEFORE = defined?(Dexpace::Transport) ? Dexpace::Transport.constants(false) : []
  require "dexpace/transport/async_http"
  TOP_LEVEL_ADDED = (Object.constants - TOP_LEVEL_BEFORE).freeze
  NAMESPACE_ADDED = (Dexpace.constants(false) - NAMESPACE_BEFORE).freeze
  SIBLINGS_ADDED = (Dexpace::Transport.constants(false) - SIBLINGS_BEFORE).freeze

  # The public surface phase 8c built into the skeleton: the transport, the policy, the six named
  # constants and phase 0's VERSION. The eight private_constants are absent from constants(false)
  # by definition.
  PUBLIC = %i[
    VERSION Adapter DropPolicy DEFAULT_TIMEOUT_SECONDS DEFAULT_CONNECTION_LIMIT MAX_ORIGINS
    REGISTRY_KEY FRAMING_HEADERS ALPN_PROTOCOLS
  ].freeze

  GEM_ROOT = File.expand_path("../../..", __dir__)
  private_constant :GEM_ROOT

  test "defines a semver VERSION string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::Transport::AsyncHTTP::VERSION)
  end

  test "the VERSION matches the gemspec this gem is built from" do
    spec = Gem::Specification.load(File.join(GEM_ROOT, "dexpace-transport-async_http.gemspec"))

    assert_equal(spec.version.to_s, Dexpace::Transport::AsyncHTTP::VERSION)
  end

  test "defines nothing outside the Dexpace namespace, and exactly its own constants inside it" do
    assert_empty(TOP_LEVEL_ADDED - [:Dexpace], "top-level constants added by the entry file")
    assert_empty(NAMESPACE_ADDED - %i[Transport], "constants added directly under Dexpace")
    assert_empty(SIBLINGS_ADDED - %i[AsyncHTTP], "constants added beside this gem's namespace")
    assert_equal(PUBLIC.sort, Dexpace::Transport::AsyncHTTP.constants(false).sort)
  end

  test "declares dexpace-core and async-http, and nothing else (NFR-2)" do
    spec = Gem::Specification.load(File.join(GEM_ROOT, "dexpace-transport-async_http.gemspec"))

    assert_equal(%w[async-http dexpace-core], spec.runtime_dependencies.map(&:name).sort)
    assert_equal(["~> 0.104"], spec.runtime_dependencies.find do |d|
      d.name == "async-http"
    end.requirement.as_list,)
  end

  # P8-36: narrower than the repository's 3.2 floor, read from VERSIONS' own per-gem row rather
  # than written twice (NFR-14).
  test "P8-36: this gem's required_ruby_version is >= 3.3, VERSIONS' per-gem floor" do
    spec = Gem::Specification.load(File.join(GEM_ROOT, "dexpace-transport-async_http.gemspec"))

    assert_equal(">= 3.3", spec.required_ruby_version.to_s)
    assert_equal("3.3", DexpaceVersions.ruby_floor("dexpace-transport-async_http"))
    assert_equal("3.2", DexpaceVersions.ruby_floor)
  end

  # The registration is proved in a bare subprocess, where nothing else has required the gem:
  # in one `rake test:gems` process the adapter's own suites load first and the key is already
  # there, so an in-process before/after snapshot would prove nothing. The child clears RUBYOPT
  # (bundler's -rbundler/setup) and inherits the parent's Gem.path instead, because async-http
  # lives in a scoped BUNDLE_PATH on this machine and in the default GEM_HOME in CI.
  test "registers itself under REGISTRY_KEY at require time; the registry resolves an adapter" do
    key = Dexpace::Transport::AsyncHTTP::REGISTRY_KEY

    assert_includes(Dexpace::AsyncTransport.registered_keys, key)
    assert_kind_of(Dexpace::Transport::AsyncHTTP::Adapter, Dexpace::AsyncTransport.resolve)
    assert_equal("[:async_http]", bare_require("p Dexpace::AsyncTransport.registered_keys").strip)
  end

  test "the registered factory builds a fresh owning adapter on every resolution (SEAM-5)" do
    first = Dexpace::Transport::AsyncHTTP.default
    second = Dexpace::Transport::AsyncHTTP.default

    refute_same(first, second)
    assert_predicate(first, :owned?)
  ensure
    first&.close
    second&.close
  end

  # Inside `module Dexpace` a bare `Async` is core's own `Dexpace::Async` (the pivot's namespace)
  # and a bare `Protocol` is phase 1's `Dexpace::Protocol`, so every reference to the socketry
  # gems under lib/ is `::`-qualified. The phase-0 cop Dexpace/QualifiedCoreConstant names
  # Thread, Queue, Mutex, SizedQueue, ConditionVariable, JSON and IO and not these -- listing
  # `Async` there would flag core's legitimate uses -- so this scan is the guard, in the shape
  # 5a's uuid_test.rb scans for SecureRandom: parsed, so a name in a comment or a message string
  # is not a reference, and a bare constant read IS whatever the lexical scope resolves it to.
  test "every Async, Protocol, OpenSSL and Console reference under lib/ is ::-qualified" do
    offenders = Dir.glob(File.join(GEM_ROOT, "lib/**/*.rb")).flat_map do |path|
      bare_constant_reads(Prism.parse_file(path).value).map do |node|
        "#{File.basename(path)}:#{node.location.start_line}: #{node.name}"
      end
    end

    assert_empty(offenders)
  end

  test "lib/ requires dexpace, async/http and openssl, and no transitive gem by name" do
    requires = Dir.glob(File.join(GEM_ROOT, "lib/**/*.rb")).flat_map do |path|
      File.read(path).scan(/^\s*require "([^"]+)"/).flatten
    end

    assert_equal(%w[async/http dexpace openssl], requires.uniq.sort)
  end

  LIBS = [File.expand_path("../../../lib", __dir__),
          File.expand_path("../../../../dexpace-core/lib", __dir__),].freeze
  private_constant :LIBS

  private

  FOREIGN = %i[Async Protocol OpenSSL Console].freeze
  private_constant :FOREIGN

  # Every ConstantReadNode -- a constant resolved through the lexical scope, never through `::`
  # -- whose name is one of the socketry gems' roots, anywhere in the tree.
  def bare_constant_reads(node, found = [])
    found << node if node.is_a?(Prism::ConstantReadNode) && FOREIGN.include?(node.name)
    node.compact_child_nodes.each { |child| bare_constant_reads(child, found) }
    found
  end

  def bare_require(program)
    command = [RbConfig.ruby, "-w", "-W:deprecated", *LIBS.flat_map { |lib| ["-I", lib] }, "-e",
               "require \"dexpace/transport/async_http\"; #{program}",]
    env = { "RUBYOPT" => nil, "GEM_PATH" => Gem.path.join(File::PATH_SEPARATOR) }
    stdout, stderr, status = Open3.capture3(env, *command)

    assert_predicate(status, :success?, stderr)
    assert_empty(stderr, "a bare require must be silent under -w")
    stdout
  end
end
