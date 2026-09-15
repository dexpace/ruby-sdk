# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SEAM-15 is a MAY -- "further send calls MAY have undefined behavior ... A port MAY choose a mode
# but SHOULD document it" -- and this port takes it explicitly: a transport that OWNS the resource
# it closed raises this from a later send. Phase 2 ships the class and the rule and no raise site,
# because it ships no owning transport; phase 8's adapters are the first owners.
class DexpaceClosedErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::ClosedError, "the transport is closed"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::ClosedError, caught)
    assert_equal("the transport is closed", caught.message)
  end

  test "is a StandardError and not a seam-state or argument error" do
    assert_operator(Dexpace::ClosedError, :<, ::StandardError)
    refute_operator(Dexpace::ClosedError, :<, ::ArgumentError)
    refute_operator(Dexpace::ClosedError, :<, Dexpace::SeamError)
  end
end
