# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# R6, P4-19: the named internal error a fold's exhaustiveness `else` arm raises. A StandardError
# that the orchestrator re-raises by name rather than converting, so a core defect is never
# demoted to an outcome a recovery step may swallow.
class DexpaceOutcomeErrorTest < DexpaceTestCase
  test "is a StandardError carrying Dexpace::Error, caught by rescue Dexpace::Error" do
    caught = begin
      raise Dexpace::OutcomeError, ::String
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::OutcomeError, caught)
    assert_kind_of(::StandardError, caught)
    assert_kind_of(Dexpace::Suppressible, caught)
  end

  # The class and not the object: an OutcomeError can end up on a suppressed trail, and
  # retaining an arbitrary value there would pin whatever it holds.
  test "carries the offending class and names it in the message" do
    error = Dexpace::OutcomeError.new(::Integer)

    assert_equal(::Integer, error.offending_class)
    assert_equal("expected a Dexpace::Outcome from a step, got an Integer", error.message)
  end

  test "refuses an offending class that is not a Module" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::OutcomeError.new("Integer") }
  end
end
