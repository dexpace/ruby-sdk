# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The Ruby facts phase 9's machinery rests on, re-measured on the interpreter running this suite
# rather than inherited from the design's planning run. Design "The verified Ruby facts this phase
# is built on"; XCUT-9, XCUT-14, NFR-4, NFR-6, NFR-17.
#
# Two facts the plan stated are corrected here against the tree as built, and each correction is
# the assertion rather than a comment:
#
#   * `.ruby-version` EXISTS and is the development pin; the plan says three times that it does
#     not, and `gates:versions` asserts the file against VERSIONS on every run.
#   * The `minitest/mock` split is invisible INSIDE the bundle, because phase 0 Task 2's
#     `minitest ~> 5.25` pin has landed: `assert_equal(major < 6, mock_available)` reduces to
#     `true == true` on every row. The honest measurement is a child process with the BUNDLE_*
#     keys cleared, which is the shape gems/dexpace-serde-json/test/dexpace/serde/json/floor_test.rb
#     uses for the same reason.
require "stringio"
require_relative "../support/gate_case"
require_relative "../support/gate_warning_capture"
require_relative "../../tools/versions"

# rubocop:disable Metrics/ClassLength -- ten interpreter facts in one file, deliberately. Each
# is a measurement this phase's scans rest on, and a second class would only move half of
# them somewhere a reader checking "is this fact still true?" would not look.
class Phase9RubyFactsTest < GateCase
  include GateWarningCapture

  WARNS_UNUSED = File.expand_path("../fixtures/gates/invariants/warns_unused.rb", __dir__)

  test "a send is one of three AST node types and a :CALL-only scan misses safe navigation" do
    types = []
    walk(::RubyVM::AbstractSyntaxTree.parse("a.cause; b&.cause; cause")) do |node|
      name = node.type == :VCALL ? node.children[0] : node.children[1]
      types << node.type if name == :cause
    end

    assert_equal(%i[CALL QCALL VCALL], types)
  end

  test "a Symbol literal is :LIT below Ruby 3.4 and :SYM at and above it" do
    found = []
    walk(::RubyVM::AbstractSyntaxTree.parse("e.send(:cause)")) do |node|
      found << node.type if %i[LIT SYM].include?(node.type)
    end
    expected = ::Gem::Version.new(::RUBY_VERSION) < ::Gem::Version.new("3.4.0") ? [:LIT] : [:SYM]

    assert_equal(expected, found,
                 "a reflective-send scan naming only one of the two is strictest on the row it " \
                 "was written on and blind on the others",)
  end

  # The PARSER is silent for well-formed input; the SCANNED FILE's own -w diagnostics are not, and
  # they arrive through Warning.warn exactly as at require time. Only under $VERBOSE: SuiteRunner
  # appends -w, so `rake test:gates` sees them and a bare `ruby test/gates/...` does not.
  test "a scanned file's own -w diagnostics reach Warning.warn, which the scanner silences" do
    skip("this fact is only observable under -w; SuiteRunner appends it") unless $VERBOSE

    seen = capture_warnings { ::RubyVM::AbstractSyntaxTree.parse_file(WARNS_UNUSED) }

    assert_equal(1, seen.size)
    assert_includes(seen.first.first, "assigned but unused variable - e")
    assert_nil(seen.first.last, "no category, so Warning[:deprecated] = false cannot reach it")
  end

  # $VERBOSE = false silences only the -w class: a duplicated hash key warns whatever $VERBOSE is
  # and would still raise under FatalWarnings, so the window AstScan.parse opens is nil, not false.
  #
  # PRESENCE and not a count: the same source emits ONE warning on 3.3.12 and later and TWO on the
  # 3.2 floor, which also reports `unused literal ignored`. The fact this test exists for is which
  # $VERBOSE value silences the class, and a count made the floor red for no property (R0-3).
  test "$VERBOSE = nil silences both warning classes, and the window closes behind it" do
    armed = $VERBOSE
    unused = capture_warnings { quietly { ::RubyVM::AbstractSyntaxTree.parse_file(WARNS_UNUSED) } }
    duplicated = capture_warnings { ::RubyVM::AbstractSyntaxTree.parse("{a: 1, a: 2}") }
    silenced = capture_warnings { quietly { ::RubyVM::AbstractSyntaxTree.parse("{a: 1, a: 2}") } }

    assert_empty(unused)
    assert(duplicated.any? { |message, _| message.include?("is duplicated") },
           "a duplicated key warns whatever $VERBOSE is",)
    assert_empty(silenced)
    assert_equal(armed, $VERBOSE, "the gate stays armed outside the window")
  end

  # The recorder is inert outside a capture block: it delegates through `super`, so whatever a
  # host has prepended below it -- DexpaceTestCase::FatalWarnings in every gem suite -- keeps its
  # behaviour. This suite runs on GateCase, which arms no raiser, so delegation is observed at
  # the real Warning.warn's own output rather than at a raise.
  test "outside a capture block the recorder delegates rather than swallowing" do
    captured = StringIO.new
    previous = $stderr
    begin
      $stderr = captured
      Warning.warn("escaped through the recorder\n")
    ensure
      $stderr = previous
    end

    assert_includes(captured.string, "escaped through the recorder")
    assert_equal(GateRecordingWarnings, Warning.singleton_class.ancestors.first,
                 "the recorder must sit ABOVE whatever else is prepended, or it never sees a call",)
  end

  test "minitest is a bundled gem, never a default one, on every supported Ruby" do
    spec = ::Gem::Specification.find_by_name("minitest")

    refute_predicate(spec, :default_gem?,
                     "design §9.3 calls minitest a default gem; it is bundled, which is why " \
                     "phase 0 Task 2's Gemfile names it",)
  end

  # Phase 0 Task 2's `minitest ~> 5.25` pin has LANDED, so inside the bundle every row is 5.x and
  # ships minitest/mock. The fact the design measured -- Minitest 6 on the 4.0 row ships none --
  # is therefore only observable OUTSIDE the bundle, and asserting it in-process would reduce to
  # `true == true` and prove nothing (this is the correction the phase's as-built record carries).
  test "inside the bundle the pin holds minitest below 6, so minitest/mock is present everywhere" do
    major = ::Gem::Version.new(::Minitest::VERSION).segments.first
    mock_available = begin
      require "minitest/mock"
      true
    rescue ::LoadError
      false
    end

    assert_operator(major, :<, 6, "phase 0 Task 2 pins minitest ~> 5.25")
    assert(mock_available, "Minitest::Mock and Object#stub are what the pin keeps available")
  end

  test "outside the bundle the interpreter's own minitest ships mock below 6 and not at 6" do
    major, available = stock_minitest

    assert_equal(major < 6, available,
                 "the framework major the interpreter ships decides minitest/mock; the pin is " \
                 "what keeps the repository off that divergence",)
  end

  test "a Data subclass's generated readers live on the superclass, not on the subclass" do
    type = Class.new(::Data.define(:code)) { def ok? = code == 200 }

    assert_equal([:ok?], type.instance_methods(false))
    assert_equal([:code], type.superclass.instance_methods(false))
    assert_predicate(type.new(code: 200), :frozen?)
  end

  test "the development pin lives in .ruby-version, which gates:versions asserts" do
    pin = File.read(File.join(ROOT, ".ruby-version")).strip

    assert_match(/\A\d+\.\d+\.\d+\z/, pin)
    assert_equal(DexpaceVersions.ruby_dev, pin)
  end

  private

  # The stock interpreter's minitest, read in a child process with every BUNDLE_*/BUNDLER_* key
  # and RUBYOPT cleared -- floor_test.rb's shape, for the same reason: inside the bundle the pin
  # answers, and the fact under test is about what the interpreter ships.
  def stock_minitest
    env = ENV.to_h.reject { |key, _| key.start_with?("BUNDLE_", "BUNDLER_", "RUBYOPT") }
    env["RUBYOPT"] = ""
    script = 'require "minitest"; ' \
             'print Gem::Version.new(Minitest::VERSION).segments.first, " "; ' \
             'print((begin; require "minitest/mock"; true; rescue LoadError; false; end))'
    out, _err, status = Open3.capture3(env, Interpreter.ruby, "-e", script, unsetenv_others: true)

    assert_predicate(status, :success?, out)
    major, available = out.split
    [Integer(major), available == "true"]
  end

  # AstScan.parse's window, spelled here so the fact is measured where it is recorded.
  def quietly
    previous = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = previous
  end

  def walk(node, &block)
    return unless node.is_a?(::RubyVM::AbstractSyntaxTree::Node)

    yield(node)
    node.children.each { |child| walk(child, &block) }
  end
end
# rubocop:enable Metrics/ClassLength
