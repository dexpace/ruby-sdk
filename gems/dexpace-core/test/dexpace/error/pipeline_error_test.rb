# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# PIPE-5, PIPE-8, PIPE-15, PIPE-18, PIPE-19, PIPE-21, PIPE-23, PIPE-24: the one class every
# composition-time and defect rejection in the pipeline subsystem is raised as (P4-37).
class DexpacePipelineErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::PipelineError, "pipeline failure"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::PipelineError, caught)
    assert_kind_of(Dexpace::Suppressible, caught)
  end

  test "subclasses StandardError and includes Dexpace::Error" do
    assert_operator(Dexpace::PipelineError, :<, ::StandardError)
    assert_includes(Dexpace::PipelineError.ancestors, Dexpace::Error)
  end

  # P4-37: one class for every composition-time and defect condition, carrying NO fields, because
  # no caller branches on the reason and a carried field would be NFR-4-locked surface with no
  # reader. The contrast is deliberate: a conflict error whose caller lost a race and may retry
  # carries the key it needs; a composition defect is fixed by editing code.
  #
  # The eleven message forms themselves are asserted where they are raised, never here -- building
  # an error and asserting its #message tests ::StandardError. Entry.build (Task 5) raises PIPE-8's;
  # Cursor#call and #fork (Task 6) raise PIPE-15's three; Builder (Task 7) raises PIPE-5's,
  # PIPE-18's, PIPE-21's, PIPE-23's, PIPE-24's and R10's two.
  test "carries no fields of its own" do
    assert_empty(Dexpace::PipelineError.instance_methods(false))
    refute_respond_to(Dexpace::PipelineError.new("x"), :stage)
  end

  test "is not Dexpace::InvalidArgumentError -- a composition defect is not a bad argument" do
    refute_operator(Dexpace::PipelineError, :<, Dexpace::InvalidArgumentError)
  end
end
