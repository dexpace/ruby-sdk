# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SEAM-21's decode half and SEAM-23's hierarchy: the decode subtype sits under the seam root, is
# caught by rescue Dexpace::Error, and is distinct from the encode subtype so a caller can rescue
# one without the other.
class DexpaceSerdeDeserializationErrorTest < DexpaceTestCase
  test "sits under the seam root and the SDK marker" do
    assert_operator(Dexpace::Serde::DeserializationError, :<, Dexpace::Serde::Error)
    assert_operator(Dexpace::Serde::DeserializationError, :<, Dexpace::Error)
    refute_operator(Dexpace::Serde::DeserializationError, :<, ::IOError)
  end

  test "is not the encode subtype, so a rescue of one does not catch the other" do
    refute_operator(Dexpace::Serde::DeserializationError, :<, Dexpace::Serde::SerializationError)
    refute_operator(Dexpace::Serde::SerializationError, :<, Dexpace::Serde::DeserializationError)

    caught = begin
      raise Dexpace::Serde::DeserializationError, "malformed"
    rescue Dexpace::Serde::SerializationError
      flunk("a decode failure must not be caught as an encode failure")
    rescue Dexpace::Serde::Error => error
      error
    end

    assert_instance_of(Dexpace::Serde::DeserializationError, caught)
  end
end
