# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CTX-8: the reject-on-duplicate loser's error names the key.
class DexpaceContextConflictErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::ContextConflictError, "k1"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::ContextConflictError, caught)
  end

  test "the message identifies the key, per CTX-8's own words" do
    error = Dexpace::ContextConflictError.new("call-key-42")

    assert_equal("call-key-42", error.call_key)
    assert_includes(error.message, "call-key-42")
  end

  test "is not Dexpace::InvalidArgumentError -- a lost race is not an invalid argument" do
    refute_operator(Dexpace::ContextConflictError, :<, Dexpace::InvalidArgumentError)
  end

  # Phase 2's three seam errors are all `< ::StandardError` with the marker included; the fourth
  # follows, so a `rescue StandardError` at an application boundary still sees it.
  test "is a StandardError carrying the Dexpace::Error marker, like phase 2's three" do
    assert_operator(Dexpace::ContextConflictError, :<, ::StandardError)
    assert_includes(Dexpace::ContextConflictError.ancestors, Dexpace::Error)
  end
end
