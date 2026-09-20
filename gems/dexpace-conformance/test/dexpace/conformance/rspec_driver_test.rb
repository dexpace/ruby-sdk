# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# The thin RSpec driver: never required by the entry file -- an RSpec-only consumer opts in with
# `require "dexpace/conformance/rspec_driver"`, exactly as it opts into RSpec -- and `::RSpec` is
# resolved inside the method body, at call time, so the file loads under a process that has never
# required the framework. This suite proves both by loading the file with no RSpec present, then
# standing a recording double in as ::RSpec for the length of one test.
class DexpaceConformanceRSpecDriverTest < DexpaceTestCase
  Assertion = Dexpace::Conformance::Assertion
  FakeSuite = Struct.new(:assertions)

  # A recording stand-in for the two RSpec entry points the driver names: `describe` collects a
  # group and `it` an example, whose body this test then runs with a context that records
  # `skip`, so what an example DOES is observable without the framework.
  module RecordingRSpec
    Example = Struct.new(:group, :description, :body)

    def self.examples
      @examples ||= []
    end

    # With a block, class_exec-shaped as RSpec's own; without one, the group, as RSpec returns.
    def self.describe(name, &block)
      group = Group.new(name)
      group.instance_eval(&block) if block
      group
    end

    # What `describe` yields: it records each `it` as an Example.
    class Group
      def initialize(name)
        @name = name
      end

      def it(description, &body)
        RecordingRSpec.examples << Example.new(@name, description, body)
      end
    end

    # What an example body runs inside: a `skip` that throws, and nothing else RSpec offers.
    class Context
      attr_reader :skipped

      def skip(message)
        @skipped = message
        throw :skipped
      end

      def run(example)
        catch(:skipped) { instance_exec(&example.body) }
        self
      end
    end
  end

  def with_fake_rspec
    if defined?(::RSpec)
      raise "a real RSpec is loaded; this suite stands a double in and must not clobber it"
    end

    Object.const_set(:RSpec, RecordingRSpec)
    RecordingRSpec.examples.clear
    yield
  ensure
    Object.send(:remove_const, :RSpec) if defined?(::RSpec) && ::RSpec.equal?(RecordingRSpec)
  end

  # Captured at load, before either test below requires the driver: the entry file must not.
  DEFINED_BY_ENTRY_FILE = Dexpace::Conformance.const_defined?(:RSpecDriver, false)

  test "the file loads with no RSpec required and defines the driver alone" do
    refute(defined?(::RSpec), "the process must not have loaded RSpec")
    refute(DEFINED_BY_ENTRY_FILE, "dexpace/conformance must not require the RSpec driver")

    require "dexpace/conformance/rspec_driver"

    assert(Dexpace::Conformance.const_defined?(:RSpecDriver, false))
    source = File.read(File.expand_path("../../../lib/dexpace/conformance/rspec_driver.rb",
                                        __dir__,))

    refute_match(/require ["']rspec/, source)
  end

  test "conformance defines one example group per assertion, each run in its own case" do
    require "dexpace/conformance/rspec_driver"
    seen = []
    suite = FakeSuite.new([
                            Assertion.build(ids: ["A"], name: "passes", body: lambda { |kase|
                              seen << kase.transport
                            },),
                            Assertion.build(ids: ["B"], name: "vacuous", body: lambda { |_|
                              raise Dexpace::Conformance::Vacuous, "none"
                            },),
                            Assertion.build(ids: ["C"], name: "waived", body: lambda { |_|
                              raise "must not run"
                            },),
                          ])
    closed = []
    transport = Object.new
    transport.define_singleton_method(:close) { closed << :closed }

    with_fake_rspec do
      Dexpace::Conformance::RSpecDriver.conformance(suite, build: lambda { |**_|
        transport
      }, waive: ["C"],)
      examples = RecordingRSpec.examples

      assert_equal(%w[passes vacuous waived], examples.map(&:group))
      assert_equal(["satisfies A", "satisfies B", "satisfies C"], examples.map(&:description))
      outcomes = examples.map { |example| RecordingRSpec::Context.new.run(example).skipped }

      assert_equal([nil, "vacuous: none", "waived: C"], outcomes)
      assert_equal(1, seen.size)
      assert_equal(%i[closed], closed, "the case is torn down after the example")
    end
  end
end
