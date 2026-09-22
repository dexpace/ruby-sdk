# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "open3"
require "rbconfig"
require_relative "../../test_helper"

# NFR-15: the version a published artifact reports at runtime is the real one. Styleguide 12.7:
# no constant outside Dexpace::. NFR-2: dexpace-core and nothing else. P8-21: the version-skew
# guard, made directly in the entry file because there is no executor registry (P2-1).
class ThreadTest < DexpaceTestCase
  # The top-level namespace is snapshotted around the require, so "defines nothing outside
  # Dexpace" holds whether this file loads alone or after the other five gems in one
  # `rake test:gems` process, where Dexpace already exists. `dexpace` itself is loaded first,
  # the way 8a's smoke suite preloads it: core's whole tree and the stdlib constants its five
  # allowlisted requires define (URI, StringScanner, SecureRandom, Date, Digest) are core's, not
  # this entry file's. The intermediate namespace is snapshotted the same way: a sibling this
  # entry file placed beside its own constant -- `Dexpace::Async::Shared` -- is outside the gem's
  # namespace and inside nothing this suite would otherwise look at.
  require "dexpace"
  TOP_LEVEL_BEFORE = Object.constants
  NAMESPACE_BEFORE = defined?(Dexpace) ? Dexpace.constants(false) : []
  SIBLINGS_BEFORE = defined?(Dexpace::Async) ? Dexpace::Async.constants(false) : []
  require "dexpace/async/thread"
  TOP_LEVEL_ADDED = (Object.constants - TOP_LEVEL_BEFORE).freeze
  NAMESPACE_ADDED = (Dexpace.constants(false) - NAMESPACE_BEFORE).freeze
  SIBLINGS_ADDED = (Dexpace::Async.constants(false) - SIBLINGS_BEFORE).freeze

  # The public surface phase 8b built into the skeleton (design, "The object model 8b ships"):
  # the pool, its rejection error, the core requirement and phase 0's VERSION. `Timer` and
  # `Pool::Job` are private_constants and absent from constants(false) by definition.
  PUBLIC = %i[VERSION REQUIRED_CORE Pool RejectedError].freeze

  test "defines a semver VERSION string" do
    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::Async::Thread::VERSION)
  end

  test "the VERSION matches the gemspec this gem is built from" do
    assert_equal(spec.version.to_s, Dexpace::Async::Thread::VERSION)
  end

  test "defines nothing outside the Dexpace namespace, and exactly its own constants inside it" do
    assert_empty(TOP_LEVEL_ADDED - [:Dexpace], "top-level constants added by the entry file")
    assert_empty(NAMESPACE_ADDED - %i[Async], "constants added directly under Dexpace")
    assert_empty(SIBLINGS_ADDED - %i[Thread], "constants added beside this gem's namespace")
    assert_equal(PUBLIC.sort, Dexpace::Async::Thread.constants(false).sort)
  end

  test "Timer is a private_constant: reachable by nothing outside the gem" do
    assert_raises(::NameError) { Dexpace::Async::Thread::Timer }
    assert_raises(::NameError) { Dexpace::Async::Thread::Pool::Job }
  end

  # The module shadows ::Thread inside its own namespace (see the CAUTION in the entry
  # file); the qualified form must still reach Ruby's own.
  test "the shadowing namespace does not hide Ruby's own Thread" do
    assert_equal("Thread", ::Thread.name)
    assert_equal("Dexpace::Async::Thread", Dexpace::Async::Thread.name)
    refute_same(::Thread, Dexpace::Async::Thread)
  end

  test "NFR-2: the gemspec declares dexpace-core and nothing else" do
    assert_equal(%w[dexpace-core], spec.runtime_dependencies.map(&:name))
  end

  # The requirement is a TWO-SEGMENT PESSIMISTIC form, never Dexpace::VERSION ("0.0.0" would be a
  # tautology), and it must AGREE with the string the gemspec declares for dexpace-core -- the
  # agreement gates:gemspec_audit checks from one side and this pins from the other (7a's
  # json_test.rb pins REQUIRED_CORE the same way).
  test "P8-21: REQUIRED_CORE is a ~> constraint equal to the gemspec's dexpace-core requirement" do
    declared = spec.runtime_dependencies.find { |d| d.name == "dexpace-core" }.requirements_list

    assert_match(/\A~>\s*\d+\.\d+\z/, Dexpace::Async::Thread::REQUIRED_CORE)
    assert_equal(declared, [Dexpace::Async::Thread::REQUIRED_CORE])
  end

  # The skewed version is passed as a plain String: #assert_core_version! takes the version
  # string precisely so the skew case is testable without redefining Dexpace::VERSION under the
  # running suite. It is private, so the probe goes through #send.
  test "P8-21: a skewed core raises SeamError naming the gem, both versions and the requirement" do
    error = assert_raises(Dexpace::SeamError) do
      Dexpace::Async::Thread.send(:assert_core_version!, "9.9.9")
    end

    assert_match(/dexpace-async-thread #{Regexp.escape(Dexpace::Async::Thread::VERSION)}/o,
                 error.message,)
    assert_match(/9\.9\.9/, error.message)
    assert_includes(error.message, Dexpace::Async::Thread::REQUIRED_CORE)
    refute_respond_to(Dexpace::Async::Thread, :assert_core_version!)
  end

  test "the running core satisfies REQUIRED_CORE, so the assertion that ran at require passed" do
    wanted = Gem::Requirement.new(Dexpace::Async::Thread::REQUIRED_CORE)

    assert(wanted.satisfied_by?(Gem::Version.new(Dexpace::VERSION)))
    assert_nil(Dexpace::Async::Thread.send(:assert_core_version!, Dexpace::VERSION))
  end

  # P8-21's "at require time, before the require_relative chain": proved in a bare subprocess
  # with a Dexpace::VERSION the requirement cannot satisfy, defined BEFORE the entry file loads
  # (core's version.rb is loaded first and the constant re-assigned under a suppressed warning),
  # so the raise is the require's own and nothing of the gem is defined afterwards.
  test "P8-21: a skewed core fails the require itself, and defines no Pool" do
    script = <<~'RUBY'
      require "dexpace/version"
      verbose, $VERBOSE = $VERBOSE, nil
      Dexpace.send(:remove_const, :VERSION)
      Dexpace.const_set(:VERSION, "9.9.9")
      $VERBOSE = verbose
      begin
        require "dexpace/async/thread"
        puts "loaded"
      rescue Dexpace::SeamError => error
        puts "seam_error: #{error.message}"
        puts "pool_defined=#{Dexpace::Async::Thread.const_defined?(:Pool, false)}"
      end
    RUBY
    out, err, status = Open3.capture3(RbConfig.ruby, "-w", "-I", core_lib, "-I", gem_lib, "-e",
                                      script,)

    assert_predicate(status, :success?, err)
    assert_match(/\Aseam_error: dexpace-async-thread .* 9\.9\.9 is loaded$/, out)
    assert_includes(out, "pool_defined=false")
  end

  private

  def spec
    Gem::Specification.load(File.expand_path("../../../dexpace-async-thread.gemspec", __dir__))
  end

  def gem_lib = File.expand_path("../../../lib", __dir__)
  def core_lib = File.expand_path("../../../../dexpace-core/lib", __dir__)
end
