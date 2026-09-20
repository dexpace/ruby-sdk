# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# Design §12's MUST-level summary counts requirements that "hold vacuously" as a category of their
# own -- Vacuous is what keeps that count true rather than something a suite's passing rate erases.
# Raised from INSIDE an assertion once it has established the antecedent is absent, never decided
# from a list outside it, so vacuity is a measurement and not a claim (8a's R7).
class DexpaceConformanceVacuousTest < DexpaceTestCase
  test "carries a reason and is a StandardError, not a Dexpace::Error and not a Failure" do
    vacuous = Dexpace::Conformance::Vacuous.new("no proxy is ever configured")

    assert_operator(Dexpace::Conformance::Vacuous, :<, ::StandardError)
    refute_operator(Dexpace::Conformance::Vacuous, :<, Dexpace::Error)
    refute_operator(Dexpace::Conformance::Vacuous, :<, Dexpace::Conformance::Failure)
    assert_equal("no proxy is ever configured", vacuous.reason)
    assert_equal("no proxy is ever configured", vacuous.message)
  end
end
