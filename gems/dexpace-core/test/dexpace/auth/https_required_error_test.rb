# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/https_required_error"

# Exercises: AUTH-28 -- the guard's error: phase 2's shape, naming the concrete step and the
# offending scheme as members and in the message.
class DexpaceAuthHTTPSRequiredErrorTest < DexpaceTestCase
  Error = Dexpace::Auth::HTTPSRequiredError

  test "phase 2's shape, carrying the step and the scheme" do
    error = Error.new(scheme: "http", step: "Dexpace::Auth::Step")

    assert_kind_of(StandardError, error)
    assert_kind_of(Dexpace::Error, error)
    assert_equal("http", error.scheme)
    assert_equal("Dexpace::Auth::Step", error.step)
  end

  test "AUTH-28: the message names the concrete step and the offending scheme" do
    message = Error.new(scheme: "ftp", step: "Dexpace::Auth::AsyncStep").message

    assert_includes(message, "Dexpace::Auth::AsyncStep")
    assert_includes(message, '"ftp"')
    assert_includes(message, "AUTH-28")
  end
end
