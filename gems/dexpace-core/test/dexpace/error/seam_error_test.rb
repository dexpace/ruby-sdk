# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SEAM-5's zero-or-ambiguous-provider failures and design §2.3's version-skew guard raise this
# class. The distinction under test is the one the design draws between a seam in a bad state --
# which the caller must fix but did not pass in -- and a bad argument, which is phase 1's
# Dexpace::InvalidArgumentError.
class DexpaceSeamErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::SeamError, "no transport provider is registered"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::SeamError, caught)
    assert_equal("no transport provider is registered", caught.message)
  end

  test "is a StandardError, so an ordinary rescue catches it" do
    assert_operator(Dexpace::SeamError, :<, ::StandardError)
  end

  # error-handling/5a185ba9 asks for a standard-library exception where one exactly fits, and
  # ArgumentError fits a bad argument -- which a missing provider is not.
  test "is not an ArgumentError, because nothing was wrong with any argument" do
    refute_operator(Dexpace::SeamError, :<, ::ArgumentError)
    refute_operator(Dexpace::SeamError, :<, Dexpace::InvalidArgumentError)
  end
end
