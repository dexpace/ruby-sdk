# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# REDIR-6: the clear error a re-send site raises when the request body is present and not
# replayable -- its message names replayability by word, so a caller reading it knows why the
# redirect was not attempted. The raise site is asserted where it happens
# (redirect/step_test.rb); this mirror pins the class's own shape. Flat under Dexpace:: on
# 6a's P6-56 precedent for the same namespace (RetryPredicateError), not under
# Dexpace::Resilience where the design named it.
class DexpaceNotReplayableErrorTest < DexpaceTestCase
  test "REDIR-6: the message names replayability and the context the raise site gives" do
    error = Dexpace::NotReplayableError.new("redirect re-issue")

    assert_match(/replayable/, error.message)
    assert_match(/redirect re-issue/, error.message)
  end

  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::NotReplayableError, "a re-send"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::NotReplayableError, caught)
    assert_kind_of(Dexpace::Suppressible, caught)
  end

  test "subclasses StandardError and includes Dexpace::Error" do
    assert_operator(Dexpace::NotReplayableError, :<, ::StandardError)
    assert_includes(Dexpace::NotReplayableError.ancestors, Dexpace::Error)
  end

  test "lives flat under Dexpace::, not under Dexpace::Resilience (6a's P6-56 precedent)" do
    assert_equal("Dexpace::NotReplayableError", Dexpace::NotReplayableError.name)
    refute(Dexpace::Resilience.const_defined?(:NotReplayableError, false))
  end
end
