# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# Exercises: PAGE-14 (the error family), SEAM-29 -- the state error a second #each on a single-use
# page view raises: a StandardError in the Dexpace::Error family and NOT an ArgumentError, so a
# caller rescuing ArgumentError around a page loop does not catch a state violation (phase 10's
# inbound bullet of 2026-09-13 on PAGE-14 / SSE-26; P7-103). The raise site is pages_test.rb.
class DexpacePagePageStateErrorTest < DexpaceTestCase
  test "PAGE-14: a Dexpace::Error, a StandardError, and never an ArgumentError" do
    error = Dexpace::Page::PageStateError.new("used twice")

    assert_kind_of(Dexpace::Error, error)
    assert_kind_of(::StandardError, error)
    refute_kind_of(::ArgumentError, error)
    refute_kind_of(Dexpace::InvalidArgumentError, error)
    assert_equal("used twice", error.message)
  end

  test "rescue Dexpace::Error catches it, through Module#===" do
    caught = begin
      raise Dexpace::Page::PageStateError, "state"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::Page::PageStateError, caught)
  end
end
