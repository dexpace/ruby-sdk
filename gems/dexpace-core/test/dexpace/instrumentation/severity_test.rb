# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/instrumentation/severity"

# Exercises: OBS-2
class DexpaceInstrumentationSeverityTest < DexpaceTestCase
  Severity = Dexpace::Instrumentation::Severity

  # OBS-2's mapping is data, not a case: the sink method and the enabled predicate are two
  # columns of one frozen table, so a fifth level cannot be added by accident and the fourth
  # cannot be mapped twice.
  test "OBS-2: exactly four levels, each mapped onto the backend's method and predicate" do
    assert_equal(%i[error warning info verbose], Severity::ALL.map(&:name))
    assert_equal(%i[error warn info debug], Severity::ALL.map(&:sink_method))
    assert_equal(%i[error? warn? info? debug?], Severity::ALL.map(&:sink_predicate))
    assert_equal([Severity::ERROR, Severity::WARNING, Severity::INFO, Severity::VERBOSE],
                 Severity::ALL,)
    assert_predicate(Severity::ALL, :frozen?)
    Severity::ALL.each { |severity| assert_predicate(severity, :frozen?) }
  end

  test "OBS-2: .of resolves each name to its constant by identity and refuses anything else" do
    assert_same(Severity::ERROR, Severity.of(:error))
    assert_same(Severity::WARNING, Severity.of(:warning))
    assert_same(Severity::INFO, Severity.of(:info))
    assert_same(Severity::VERBOSE, Severity.of(:verbose))

    [:unknown, :warn, "info", nil, 3].each do |name|
      error = assert_raises(Dexpace::InvalidArgumentError, name.inspect) { Severity.of(name) }
      assert_includes(error.message, name.inspect)
    end
  end

  # The construction-pattern validator behind the private constructor, reached the one way it
  # can be: `send` bypasses `private`, a documented property of Ruby the pattern states
  # honestly (P8), and the validator is what a forged construction meets.
  test "OBS-2: the private constructor refuses a member that is not a Symbol" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Severity.send(:new, name: "error", sink_method: :error, sink_predicate: :error?)
    end

    assert_match(/must be a Symbol/, error.message)
  end

  # The set is closed at four, structurally: no public constructor and no derivation, the shape
  # Pipeline::Stage takes (P4-32).
  test "OBS-2: the set is closed -- no constructor, no derivation, four constants" do
    refute_respond_to(Severity, :new)
    refute_respond_to(Severity, :[])
    refute_respond_to(Severity, :build)
    assert_raises(Dexpace::InvalidArgumentError) { Severity::INFO.with(name: :other) }
    assert_equal(4, Severity::ALL.size)
    assert_equal(Severity::ALL.size, Severity::ALL.uniq.size)
  end
end
