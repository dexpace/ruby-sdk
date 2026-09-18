# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/unencodable_credential_error"
require_relative "../../../lib/dexpace/each_cause"

# Exercises: AUTH-21 (R10, P6-1), AUTH-8 -- the typed failure: phase 2's error shape under the
# Auth namespace, the field, the target encoding and the value's own encoding as members and in
# the message, never the value, the reason worded for the branch that raised (6c's P6-84), and
# no cause at all (6c's P6-85).
class DexpaceAuthUnencodableCredentialErrorTest < DexpaceTestCase
  Error = Dexpace::Auth::UnencodableCredentialError

  test "phase 2's shape, namespaced under Auth" do
    error = Error.new(field: :password, encoding: "ISO-8859-1", source_encoding: "UTF-8")

    assert_kind_of(StandardError, error)
    assert_kind_of(Dexpace::Error, error)
    assert_equal(:password, error.field)
    assert_equal("ISO-8859-1", error.encoding)
    assert_equal("UTF-8", error.source_encoding)
  end

  test "the message names the field and both encodings and says why the target applied" do
    message = Error.new(field: :username, encoding: "ISO-8859-1", source_encoding: "UTF-8").message

    assert_includes(message, "username")
    assert_includes(message, "cannot be encoded as ISO-8859-1 from UTF-8")
    assert_includes(message, "did not advertise charset=UTF-8")
    assert_includes(message, "AUTH-21")
  end

  # The rescued conversion error named a character of the secret and #full_message renders a
  # cause (review round 1's R1-3): the type takes no cause and the handler raises it with none.
  test "AUTH-8 (P6-85): the error is raised with no cause, so #full_message shows only itself" do
    error = assert_raises(Error) do
      raise "in flight"
    rescue StandardError
      raise Error.new(field: :password, encoding: "UTF-8", source_encoding: "ASCII-8BIT"),
            cause: nil
    end

    assert_nil(error.cause)
    assert_equal([error], Dexpace.each_cause(error).to_a)
    refute_includes(error.full_message(highlight: false), "in flight")
  end

  # The reason is the target's own (review round 0's R0-3): the UTF-8 branch must not blame
  # the challenge for a byte the caller supplied.
  test "the UTF-8 branch's message says the challenge advertised it, never that it did not" do
    message = Error.new(field: :password, encoding: "UTF-8", source_encoding: "ASCII-8BIT").message

    assert_includes(message, "password cannot be encoded as UTF-8 from ASCII-8BIT")
    assert_includes(message, "advertised charset=UTF-8")
    refute_includes(message, "did not advertise")
    refute_includes(message, "ISO-8859-1")
    other = Error.new(field: :realm, encoding: "UTF-16", source_encoding: "UTF-8").message

    assert_includes(other, "UTF-16")
  end
end
