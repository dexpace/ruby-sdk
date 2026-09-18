# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/provider_error"

# Exercises: AUTH-35, AUTH-11 -- the provider-misbehaviour error's shape.
class DexpaceAuthProviderErrorTest < DexpaceTestCase
  test "phase 2's shape, namespaced under Auth, message-only" do
    error = Dexpace::Auth::ProviderError.new("the provider returned no token (AUTH-35)")

    assert_kind_of(StandardError, error)
    assert_kind_of(Dexpace::Error, error)
    assert_equal("the provider returned no token (AUTH-35)", error.message)
  end
end
