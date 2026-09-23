# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The three repository-wide invariant scans. XCUT-9, XCUT-14, SEAM-2; design R4.
#
# A scanner that let a scanned file's own -w diagnostic reach `Warning.warn` would redden any
# suite with a warnings-fatal hook over a file it merely READS. That property is proven here by
# RECORDING the warning rather than by arming the raiser: `test/gates/` runs on GateCase, which
# does not install FatalWarnings, and installing it from a support file arms it for the whole
# process -- where three deliberately-invalid gemspec fixtures and YARD's own load-time warnings
# had always reached Warning.warn harmlessly.
require_relative "../support/gate_case"
require_relative "../support/gate_warning_capture"
require_relative "../../tools/invariant_gates"

# rubocop:disable Metrics/ClassLength -- three scans, each with its own fixture, its own
# allowlist and its own rake task, in the one file a reader checking "do the invariant
# gates still hold?" opens.
class InvariantGatesTest < GateCase
  include GateWarningCapture

  FIXTURES = File.expand_path("../fixtures/gates/invariants", __dir__)

  def fixture(name) = File.join(FIXTURES, name)

  # ---- gates:cause_walk ----

  test "cause_walk reports CALL, QCALL, VCALL, FCALL and &:cause, not an argument-carrying send" do
    offences = InvariantGates.cause_walk([fixture("walks_cause.rb")])

    assert_equal(5, offences.size,
                 "six sends named cause; 5b's builder shape .cause(error) is not a walk",)
    assert_includes(offences.first, "XCUT-9")
  end

  test "cause_walk reports every reflective send shape, by Symbol and by String" do
    offences = InvariantGates.cause_walk([fixture("reflective_cause.rb")])

    assert_equal(7, offences.size,
                 "send/__send__/public_send/method by Symbol, send by String, plus . and &. -- " \
                 "7 of 8; send(variable) is undecidable and is the gate's stated gap",)
  end

  test "cause_walk is clean for a file that delegates and names cause only in prose" do
    assert_empty(InvariantGates.cause_walk([fixture("delegates_cause.rb")]))
  end

  test "cause_walk honours its allowlist so the single walk's own file passes" do
    assert_empty(InvariantGates.cause_walk([fixture("walks_cause.rb")],
                                           allowed: [fixture("walks_cause.rb")],))
  end

  # ---- gates:bounded_map ----

  test "bounded_map reports every statically decidable Hash shape" do
    offences = InvariantGates.bounded_map([fixture("hash_shapes.rb")], allowed: {})

    assert_equal(5, offences.size,
                 "literal, Hash.new, ::Hash.new, a chained call on a literal and an ||= -- " \
                 "5 of 7; a method return and a parameter are the stated gap",)
    assert_includes(offences.first, "XCUT-14")
  end

  test "bounded_map is clean when the file is allowlisted with a reason" do
    allowed = { fixture("hash_shapes.rb") => "keys are frozen constants, not caller input" }

    assert_empty(InvariantGates.bounded_map([fixture("hash_shapes.rb")], allowed: allowed))
  end

  # The allowlist IS the adjudication, so a stale entry silently re-opens a hole. The planning
  # adjudication named `configuration.rb`, which holds no Hash ivar at all -- 5a's accumulators
  # are in `configuration/builder.rb` -- and a check that only asserted the file EXISTS passed
  # over it for a whole round. So this asserts both halves: the path exists AND the scan still
  # reports there. XCUT-14.
  test "every bounded_map allowlist entry names a live file that the scan still reports" do
    refute_empty(InvariantGates::BOUNDED_MAP_ALLOWED)

    InvariantGates::BOUNDED_MAP_ALLOWED.each do |path, reason|
      absolute = File.join(ROOT, path)

      assert_path_exists(absolute, "allowlisted path no longer exists; the entry is stale")
      refute_empty(reason.to_s.strip, "#{path} is allowlisted with no reason")
      refute_empty(InvariantGates.bounded_map([absolute], allowed: {}),
                   "#{path} is allowlisted but the scan reports nothing there, so the entry " \
                   "silences nothing -- which is exactly how a stale entry survives",)
    end
  end

  # ---- gates:seam_names ----

  test "seam_names matches an adapter's leaf namespace, not a literal spelling" do
    offences = InvariantGates.seam_names([fixture("seam_shapes.rb")])

    assert_equal(7, offences.size,
                 "qualified, root-qualified, bare, a const_get String, a const_get Symbol and a " \
                 "leaf pair deeper in a path, which reports at both levels",)
  end

  test "seam_names permits core's own constants in the seam namespaces" do
    offences = InvariantGates.seam_names([fixture("seam_shapes.rb")]).join("\n")

    refute_includes(offences, "Dexpace::Registry")
    refute_includes(offences, "Serde::Error")
    refute_includes(offences, "Async::Future")
    refute_includes(offences, "Instrumentation::Severity")
  end

  # ---- the scanner's own warning window ----

  # A scanned file's own -w diagnostics reach Warning.warn like any other parse. The first
  # assertion proves the fixture is not inert; the third proves AstScan.parse's $VERBOSE window
  # holds. Only under -w: SuiteRunner appends it, so `rake test:gates` sees this and a bare
  # `ruby test/gates/...` does not.
  test "a file whose own -w diagnostics reach Warning.warn is scanned without emitting one" do
    unless $VERBOSE
      skip("the fixture's diagnostic is only emitted under -w; SuiteRunner appends it")
    end

    bare = capture_warnings { ::RubyVM::AbstractSyntaxTree.parse_file(fixture("warns_unused.rb")) }
    through_the_gate = capture_warnings { InvariantGates.cause_walk([fixture("warns_unused.rb")]) }

    assert_equal(1, bare.size, "the fixture is inert, so this test could not discriminate")
    assert_includes(bare.first.first, "assigned but unused variable - e")
    assert_empty(through_the_gate, "AstScan.parse's $VERBOSE window did not hold")
  end

  test "the scanner leaves $VERBOSE exactly as it found it" do
    armed = $VERBOSE
    InvariantGates.cause_walk([fixture("delegates_cause.rb")])

    assert_equal(armed, $VERBOSE)
  end

  # ---- the three gates over the real tree ----

  test "all three gates are clean over this repository, which is what makes them blocking" do
    lib = Dir.glob("gems/*/lib/**/*.rb", base: ROOT).map { |path| File.join(ROOT, path) }
    core = Dir.glob("gems/dexpace-core/lib/**/*.rb", base: ROOT).map do |path|
      File.join(ROOT, path)
    end
    allowed = InvariantGates::BOUNDED_MAP_ALLOWED.transform_keys { |key| File.join(ROOT, key) }

    assert_empty(InvariantGates.cause_walk(lib, allowed: [File.join(ROOT, *CAUSE_WALK)]))
    assert_empty(InvariantGates.bounded_map(lib, allowed: allowed))
    assert_empty(InvariantGates.seam_names(core))
  end

  CAUSE_WALK = ["gems/dexpace-core/lib/dexpace/each_cause.rb"].freeze

  # ---- the three RAKE TASKS, against a deliberately failing workspace ----

  # Every repository-reading gate here accepts DEXPACE_GATE_ROOT and is driven against a fixture
  # that must fail it. These three were not, and the omission hid a real defect: the tasks handed
  # the scanner paths made relative to `root`, which the scanner then opened relative to the
  # PROCESS'S CWD -- the same directory only when DEXPACE_GATE_ROOT is unset. Under a fixture root
  # every open raised Errno::ENOENT, so the tasks could never have been shown to reject anything.
  # Found and fixed in this phase; these three tests are what keep it fixed.
  WORKSPACE = File.join(FIXTURES, "workspace")

  test "the cause_walk task rejects a fixture workspace, with its allowlist under that root" do
    _out, err, status = rake("gates:cause_walk", "DEXPACE_GATE_ROOT" => WORKSPACE)

    refute_predicate(status, :success?)
    assert_includes(err, "gems/dexpace-core/lib/dexpace/offender.rb:10")
    assert_includes(err, "XCUT-9")
    refute_includes(err, "each_cause.rb",
                    "the allowlist was joined to the CWD rather than to the gate root",)
  end

  test "the bounded_map task rejects a fixture workspace, reaching a gem that is not core" do
    _out, err, status = rake("gates:bounded_map", "DEXPACE_GATE_ROOT" => WORKSPACE)

    refute_predicate(status, :success?)
    assert_includes(err, "gems/dexpace-probe/lib/dexpace/probe/cache.rb")
    assert_includes(err, "@by_origin")
    assert_includes(err, "XCUT-14")
  end

  test "the seam_names task rejects a fixture workspace and scans core alone" do
    _out, err, status = rake("gates:seam_names", "DEXPACE_GATE_ROOT" => WORKSPACE)

    refute_predicate(status, :success?)
    assert_includes(err, "gems/dexpace-core/lib/dexpace/offender.rb")
    assert_includes(err, "Dexpace::Serde::JSON")
    refute_includes(err, "dexpace-probe", "seam_names is core's scan, not every gem's")
  end

  test "all three tasks pass over this repository, which is what makes them blocking" do
    %w[gates:cause_walk gates:bounded_map gates:seam_names].each do |task|
      out, err, status = rake(task)

      assert_predicate(status, :success?, "#{task}: #{err}")
      assert_includes(out, task)
    end
  end
end
# rubocop:enable Metrics/ClassLength
