# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# The thin Minitest driver (design §9.3, 8a's R7): one generated test method per assertion, each
# running its OWN assertion in a fresh TransportCase, a Vacuous reported as a skip, a Failure as a
# flunk naming the ids, a waived id as a skip that names it, and the case torn down whatever
# happened. Named MinitestDriver and not Minitest: inside module Dexpace::Conformance a constant
# named Minitest would shadow ::Minitest for the whole namespace (5a's P5-3 reasoning).
#
# The suite handed in is a plain object answering #assertions -- no `.stub`, so no fence here
# needs `minitest/mock` -- and every driven class overrides .runnable_methods to return nothing,
# so it is driven only through Minitest.run_one_method below and never by the outer run. Two
# nested classes under Metrics/ClassLength (6c's shape).
module DexpaceConformanceMinitestDriverTest
  Assertion = Dexpace::Conformance::Assertion
  Failure = Dexpace::Conformance::Failure

  # Anything shaped like TransportSuite: an ordered #assertions.
  FakeSuite = Struct.new(:assertions)

  # The driven-class builder and the one-method runner both classes share.
  module Driving
    def assertion(id, name, &body)
      Assertion.build(ids: [id], name: name, body: body)
    end

    def driven(suite, **options)
      Class.new(DexpaceTestCase) do
        extend Dexpace::Conformance::MinitestDriver

        # Kept out of the outer run: this class exists to be driven by run_one_method alone.
        def self.runnable_methods
          []
        end

        conformance(suite, **options)
      end
    end

    def generated(klass)
      klass.public_instance_methods(false).grep(/\Atest_/).map(&:to_s).sort
    end

    def drive(klass, method_name)
      ::Minitest.run_one_method(klass, method_name)
    end

    def drive_one(assertion, **)
      klass = driven(FakeSuite.new([assertion]), **)
      drive(klass, generated(klass).first)
    end
  end

  # The generated methods and the outcomes each maps to.
  class OutcomesTest < DexpaceTestCase
    include Driving

    test "conformance defines one test method per assertion, named from the assertion's name" do
      suite = FakeSuite.new([assertion("A", "passes cleanly") { |_| nil },
                             assertion("B", "also passes: with punctuation!") { |_| nil },])

      klass = driven(suite, build: ->(**_) { :t })

      assert_equal(%w[test_also_passes_with_punctuation test_passes_cleanly], generated(klass))
    end

    test "the generated test runs the assertion in a fresh case built from the driver's factory" do
      built = []
      seen = nil
      transport = Object.new
      transport.define_singleton_method(:close) { built << :closed }
      build = lambda do |**_|
        built << :built
        transport
      end

      result = drive_one(assertion("A", "sees the case") do |kase|
        seen = kase
        kase.transport
      end, build: build,)

      assert_predicate(result, :passed?)
      assert_kind_of(Dexpace::Conformance::TransportCase, seen)
      assert_equal(%i[built closed], built, "built by the factory, torn down in the ensure")
    end

    test "a Failure flunks the generated test, naming the ids and the message" do
      result = drive_one(assertion("TRANSPORT-24", "fails") do |_|
        raise Failure.new("status was 200", expected: 520, actual: 200,
                                            requirement_ids: ["TRANSPORT-24"],)
      end, build: ->(**_) { :t },)

      refute_predicate(result, :passed?)
      refute_predicate(result, :error?)
      assert_match(/TRANSPORT-24: status was 200/, result.failure.message)
    end

    test "a Vacuous skips the generated test, naming the reason" do
      result = drive_one(assertion("A", "vacuous") do |_|
        raise Dexpace::Conformance::Vacuous, "no antecedent here"
      end, build: ->(**_) { :t },)

      assert_predicate(result, :skipped?)
      assert_match(/vacuous: no antecedent here/, result.failure.message)
    end

    test "a waived id skips the generated test without running the body, naming the id" do
      ran = false
      result = drive_one(assertion("TRANSPORT-28", "waivable") { |_| ran = true },
                         build: ->(**_) { :t }, waive: ["TRANSPORT-28"],)

      assert_predicate(result, :skipped?)
      assert_match(/waived: TRANSPORT-28/, result.failure.message)
      refute(ran)
    end

    test "any other raise is an error, never silently a failure or a pass" do
      result = drive_one(assertion("A", "errors") { |_| raise "boom" }, build: ->(**_) { :t })

      assert_predicate(result, :error?)
    end
  end

  # The three keywords an async driver passes, and the driver's own independence of the framework.
  class ContractTest < DexpaceTestCase
    include Driving

    # Clauses 8, 9 and 11 (8a's R16): the three keywords reach the case the generated test builds,
    # and a sync driver passing none gets the defaults.
    test "settle:, around: and wire: reach the case; the guard still refuses a direct #call" do
      order = []
      seen = []
      probe = assertion("A", "probes") do |kase|
        seen << kase.settle(kase.transport, :req, :opts, :cancel)
        seen << kase.wire(script: :s)
        begin
          kase.transport.call(:r, :o, :c)
        rescue ArgumentError
          seen << :guarded
        end
        order << :assertion
      end
      around = lambda do |&blk|
        order << :before
        blk.call
        order << :after
      end

      result = drive_one(probe, build: ->(**_) { :t }, settle: ->(_t, _r, _o, _c) { :settled },
                                wire: ->(script) { [:wired, script] }, around: around,)

      assert_predicate(result, :passed?, result.failure&.message)
      assert_equal([:settled, %i[wired s], :guarded], seen)
      assert_equal(%i[before assertion after], order)
    end

    test "the driver requires no framework itself and names ::Minitest nowhere in its source" do
      path = File.expand_path("../../../lib/dexpace/conformance/minitest_driver.rb", __dir__)
      source = File.read(path)

      refute_match(/require ["']minitest/, source)
      refute_match(/\bMinitest\b(?!Driver)/, source.lines.grep_v(/^\s*#/).join)
    end
  end
end
