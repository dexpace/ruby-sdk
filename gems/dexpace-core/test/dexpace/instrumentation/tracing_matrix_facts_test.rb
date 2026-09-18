# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fiber_storage_facts"
require_relative "../../support/warning_capture"
require_relative "../../support/recording_span"
require_relative "../../support/recording_tracer"
require_relative "../../support/recording_meter"

# OBS-21, OBS-23, OBS-25, OBS-27, OBS-29, OBS-30, OBS-31, OBS-33: the floor-straddling facts the
# segment rests on (the design's facts 2, 3, 4 and 6), re-run on every interpreter in the matrix
# as a standing test, plus the VM measurements behind P5-42 and P5-46 and the shape of the three
# recording fakes P5-48 makes every recording-branch assertion run against. Two facts the design
# measured on 3.4.10 alone turned out NOT to hold on the floor, and the assertions below pin the
# boundary rather than the 3.4.10 answer (support/fiber_storage_facts.rb says what follows).
#
# Split into nested classes under Metrics/ClassLength, one per fact family.
class DexpaceInstrumentationTracingMatrixFactsTest < DexpaceTestCase
  include FiberStorageFacts

  FROZEN = { "k" => "v" }.freeze
  SLOT = :"dexpace.fact.slot"
  ARR = :"dexpace.fact.arr"
  LOCAL = :"dexpace.fact.local"
  FLOOR = ::Gem::Version.new(::RUBY_VERSION) < ::Gem::Version.new("3.3")
  PRE_3_4 = ::Gem::Version.new(::RUBY_VERSION) < ::Gem::Version.new("3.4")

  def teardown
    ::Fiber[SLOT] = nil
    ::Fiber[ARR] = nil
    super
  end

  # Fact 4, the floor half: `Fiber[:k] = nil` deletes on 3.3+ and retains a nil on 3.2, and the
  # per-key setter warns nowhere on any row.
  test "fact 4: Fiber[:k] = nil deletes the key from 3.3 and retains it with nil on 3.2" do
    ::Fiber[SLOT] = "exists"

    assert(::Fiber.current.storage.key?(SLOT))

    ::Fiber[SLOT] = nil

    assert_nil(::Fiber[SLOT])
    assert_equal(!FLOOR, NIL_ASSIGNMENT_DELETES, "the boundary is 3.3.0")
    assert_equal(!FLOOR, !::Fiber.current.storage.key?(SLOT))
  end

  # Fact 4, the whole-map half: the warned setter retains a nil-valued key on every row -- the
  # one way a present-and-null key exists (P5-49) -- and warns once per call at the default
  # level, which is why core never calls it. WarningCapture records the warning the shared base
  # would otherwise raise on; the storage is put back through the same setter.
  test "fact 4: Fiber#storage= retains a nil-valued key and warns on every call" do
    before = ::Fiber.current.storage
    warnings = WarningCapture.record do
      ::Fiber.current.storage = before.merge(SLOT => nil)
      ::Fiber.current.storage = before.merge(SLOT => nil)
    end

    assert(::Fiber.current.storage.key?(SLOT))
    assert_nil(::Fiber[SLOT])
    assert_equal(2, warnings.size)
    assert_match(/Fiber#storage= is experimental/, warnings.first)
  ensure
    WarningCapture.record { ::Fiber.current.storage = before }
  end

  # Fact 3: a String key is interned by the per-key API from 3.4 and refused before it, while the
  # whole-map setter refuses one everywhere; Symbol#name is identity-stable on every row.
  test "fact 3: Fiber[String] interns from 3.4 and raises TypeError on 3.2 and 3.3" do
    assert_equal(!PRE_3_4, STRING_KEY_INTERNED, "the boundary is 3.4.0")
    if STRING_KEY_INTERNED
      ::Fiber["dexpace.fact.slot"] = "s"

      assert_equal("s", ::Fiber[SLOT])
      assert(::Fiber.current.storage.key?(SLOT))
    else
      assert_raises(::TypeError) { ::Fiber["dexpace.fact.slot"] = "s" }
      assert_raises(::TypeError) { ::Fiber["dexpace.fact.slot"] }
    end
    assert_raises(::TypeError) do
      WarningCapture.record { ::Fiber.current.storage = { "dexpace.fact.slot" => "s" } }
    end
  end

  test "fact 3: Symbol#name is the same frozen String on every call; #to_s is not" do
    sym = :"trace.id"

    assert_same(sym.name, sym.name)
    assert_predicate(sym.name, :frozen?)
    refute_same(sym.to_s, sym.to_s)
    refute_same(sym.name, "trace.id")
  end

  test "fact 3: Fiber.current.storage is a fresh unfrozen Hash per read, Symbol-keyed" do
    ::Fiber[SLOT] = "s"
    first = ::Fiber.current.storage

    refute_same(first, ::Fiber.current.storage)
    refute_predicate(first, :frozen?)

    first.delete(SLOT)

    assert(::Fiber.current.storage.key?(SLOT), "mutating the copy changes nothing")
    assert(::Fiber.current.storage.keys.all?(::Symbol))
  end

  # Fact 2: copy-on-write protects the slot and not the object in it, on every row.
  test "fact 2: a rebinding in a child stays in the child; a mutation reaches the parent" do
    ::Fiber[SLOT] = :parent
    ::Fiber[ARR] = []
    ::Thread.new { ::Fiber[SLOT] = :child }.join
    ::Fiber.new { ::Fiber[SLOT] = :child }.resume

    assert_equal(:parent, ::Fiber[SLOT])

    child_id = ::Thread.new { ::Fiber[ARR].push(:t).object_id }.value
    ::Fiber.new { ::Fiber[ARR] << :f }.resume

    assert_equal(%i[t f], ::Fiber[ARR])
    assert_equal(::Fiber[ARR].object_id, child_id)
  end

  test "fact 2: Fiber[] reaches a child fiber, a thread and an enumerator; Thread.current[] none" do
    ::Fiber[SLOT] = :parent
    ::Thread.current[LOCAL] = :thread_local
    seen = [
      ::Fiber.new { [::Fiber[SLOT], ::Thread.current[LOCAL]] }.resume,
      ::Thread.new { [::Fiber[SLOT], ::Thread.current[LOCAL]] }.value,
      ::Enumerator.new { |y| y << [::Fiber[SLOT], ::Thread.current[LOCAL]] }.next,
    ]

    assert_equal([[:parent, nil]] * 3, seen)
  ensure
    ::Thread.current[LOCAL] = nil
  end

  # Fact 6: securerandom is a permanently-default gem, its require loads no openssl, and both
  # draws OBS-27 uses have the shape the flavours' patterns demand.
  class SecureRandomFacts < DexpaceTestCase
    test "fact 6: securerandom is not in Gem::BUNDLED_GEMS::SINCE where that table exists" do
      require "securerandom"
      if defined?(::Gem::BUNDLED_GEMS::SINCE)
        assert_nil(::Gem::BUNDLED_GEMS::SINCE["securerandom"])
      else
        assert_operator(::Gem::Version.new(::RUBY_VERSION), :<, ::Gem::Version.new("3.3"))
      end

      assert_match(/\A[0-9a-f]{32}\z/, ::SecureRandom.hex(16))
      assert_kind_of(::Integer, ::SecureRandom.random_number(1 << 64))
    end

    # In a fresh process with the bundler environment scrubbed, because two things in the suite's
    # own process load openssl and neither is securerandom: `test:gems` runs the six suites in one
    # process where another gem's tooling may already have required it (which made the in-place
    # $LOADED_FEATURES read order-dependent on 3.4.10), and `bundle exec` exports
    # `RUBYOPT=-rbundler/setup`, which a child interprets before `-e` and whose setup on 3.4.10
    # requires openssl itself (fifteen features, measured). What the fact claims is what
    # `require "securerandom"` loads on its own.
    test "fact 6: requiring securerandom alone loads no openssl" do
      program = 'require "securerandom"; puts $LOADED_FEATURES.grep(/openssl/).size'
      scrub = { "RUBYOPT" => nil, "RUBYLIB" => nil, "BUNDLE_GEMFILE" => nil,
                "BUNDLER_SETUP" => nil, "BUNDLE_BIN_PATH" => nil, }
      out = IO.popen(scrub, [::RbConfig.ruby, "-e", program], err: %i[child out], &:read)

      assert_equal("0\n", out)
    end
  end

  # Facts 1, 5 and 7: the VM measurements P5-42 and P5-46 rest on, and the identity across
  # threads OBS-30's structural safety rests on. Only frozen constants cross the loop body.
  class AllocationFacts < DexpaceTestCase
    # A plain three-ivar object, the shape Scope takes (P5-46). A normal `def`, because a
    # parallel assignment inside an endless one allocates an Array per call (measured: 2003).
    class Plain
      def initialize(one, two, three)
        @one = one
        @two = two
        @three = three
      end
    end

    Triple = ::Data.define(:one, :two, :three)

    def measure(&)
      ::GC.disable
      start = ::GC.stat(:total_allocated_objects)
      1000.times(&)
      ::GC.stat(:total_allocated_objects) - start
    ensure
      ::GC.enable
    end

    def sample_splat(_value, **_attributes) = nil
    def sample_named(_value, attributes: nil) = attributes

    test "fact 1: a ** splat allocates a Hash per call; a named optional keyword does not" do
      assert_operator(measure { sample_splat(1) }, :>=, 1000)
      assert_operator(measure { sample_named(1) }, :<, 10)
      assert_operator(measure { sample_named(1, attributes: FROZEN) }, :<, 10)
    end

    test "fact 5: a three-ivar object is one allocation and a Data is at least two" do
      assert_operator(measure { Plain.new(1, 2, 3) }, :<, 1100)
      assert_operator(measure { Triple.new(1, 2, 3) }, :>=, 2000)
    end

    test "fact 7: a frozen singleton is the same object from sixteen threads" do
      singleton = ::Object.new.freeze
      results = Array.new(16) { ::Thread.new { singleton } }.map(&:value)

      results.each { |seen| assert_same(singleton, seen) }
    end
  end

  # The three recording fakes P5-48 makes every recording-branch assertion run against, driven
  # red before the doubles existed (the LoadError the plan's Task 1 Step 3 names).
  class DoublesContract < DexpaceTestCase
    test "the recording span records and latches its finish" do
      span = Dexpace::RecordingSpan.new

      assert_predicate(span, :recording?)
      assert_same(span, span.set_attribute("k", "v"))
      assert_equal("v", span.attributes["k"])
      assert_nil(span.finish)
      assert_nil(span.finish)
      assert_equal(1, span.finished_at.size)
      refute_predicate(Dexpace::RecordingSpan.new(recording: false), :recording?)
    end

    test "the recording factory mints a fresh tracer per call under 4a's five-argument shape" do
      factory = Dexpace::RecordingTracerFactory.new
      tracer = factory.tracer("op", "1.0")
      other = factory.tracer(name: "op", version: "1.0")

      refute_same(tracer, other)
      assert_equal(["op", "1.0"], [tracer.name, tracer.version])
      assert_equal(["op", "1.0"], [other.name, other.version])
      assert_equal([tracer, other], factory.tracers)
      assert_instance_of(Dexpace::RecordingSpan, tracer.start_span("s"))
    end

    test "the recording meter mints a fresh instrument per call and records verbatim" do
      meter = Dexpace::RecordingMeter.new
      counter = meter.create_counter("c", unit: "{request}")
      histogram = meter.create_histogram("h", unit: "ms", description: "latency")

      refute_same(counter, meter.create_counter("c", unit: "{request}"))
      assert_nil(counter.add(2, attributes: FROZEN))
      assert_nil(histogram.record(Float::NAN))
      assert_equal([{ amount: 2, attributes: FROZEN }], counter.records)
      assert_predicate(histogram.records.first[:amount], :nan?)
      assert_equal(2, meter.counters.size)
      assert_equal([histogram], meter.histograms)
    end
  end
end
