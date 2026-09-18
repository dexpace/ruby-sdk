# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/error/auth_resolution_error"
require_relative "../../../lib/dexpace/auth/scheme"

# Exercises: AUTH-6 -- the distinct resolution error: phase 2's error shape, both lists carried
# as frozen members in the order given, and a message naming the schemes.
class DexpaceAuthResolutionErrorTest < DexpaceTestCase
  Scheme = Dexpace::Auth::Scheme

  test "phase 2's shape: a StandardError carrying the Dexpace::Error marker, flat under Dexpace" do
    error = Dexpace::AuthResolutionError.new(required: [Scheme::DIGEST], available: [])

    assert_kind_of(StandardError, error)
    assert_kind_of(Dexpace::Error, error)
    refute_kind_of(Dexpace::InvalidArgumentError, error)
  end

  test "carries the required schemes in preference order and the available ones, frozen copies" do
    required = [Scheme::DIGEST, Scheme::BASIC]
    available = [Scheme::API_KEY]
    error = Dexpace::AuthResolutionError.new(required: required, available: available)
    required << Scheme::OAUTH2

    assert_equal([Scheme::DIGEST, Scheme::BASIC], error.required)
    assert_equal([Scheme::API_KEY], error.available)
    assert_predicate(error.required, :frozen?)
    assert_predicate(error.available, :frozen?)
  end

  test "the message names both lists, and an empty available list as (none)" do
    error = Dexpace::AuthResolutionError.new(required: [Scheme::DIGEST, Scheme::BASIC],
                                             available: [],)

    assert_equal("no satisfiable auth scheme: required DIGEST, BASIC in preference order, " \
                 "available (none) (AUTH-6)", error.message,)
  end
end
