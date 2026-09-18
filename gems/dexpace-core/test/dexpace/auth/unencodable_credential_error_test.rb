# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/unencodable_credential_error"

# Exercises: AUTH-21 (R10, P6-1) -- the typed failure: phase 2's error shape under the Auth
# namespace, the field and the encoding as members and in the message, never the value.
class DexpaceAuthUnencodableCredentialErrorTest < DexpaceTestCase
  Error = Dexpace::Auth::UnencodableCredentialError

  test "phase 2's shape, namespaced under Auth" do
    error = Error.new(field: :password, encoding: "ISO-8859-1")

    assert_kind_of(StandardError, error)
    assert_kind_of(Dexpace::Error, error)
    assert_equal(:password, error.field)
    assert_equal("ISO-8859-1", error.encoding)
  end

  test "the message names the field and the encoding and says why the encoding applied" do
    message = Error.new(field: :username, encoding: "ISO-8859-1").message

    assert_includes(message, "username")
    assert_includes(message, "ISO-8859-1")
    assert_includes(message, "charset=UTF-8")
    assert_includes(message, "AUTH-21")
  end
end
