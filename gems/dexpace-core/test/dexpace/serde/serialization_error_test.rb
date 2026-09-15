# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SEAM-20's encode half and SEAM-23's hierarchy: the encode subtype sits under the seam root, is
# caught by rescue Dexpace::Error, and chains the backing library's failure as #cause when raised
# from inside its rescue.
class DexpaceSerdeSerializationErrorTest < DexpaceTestCase
  test "sits under the seam root and the SDK marker" do
    assert_operator(Dexpace::Serde::SerializationError, :<, Dexpace::Serde::Error)
    assert_operator(Dexpace::Serde::SerializationError, :<, Dexpace::Error)
    refute_operator(Dexpace::Serde::SerializationError, :<, ::IOError)
  end

  test "raised from inside a rescue, it chains the original as the cause" do
    caught = begin
      begin
        raise "the encoder refused the value"
      rescue ::RuntimeError
        raise Dexpace::Serde::SerializationError, "encode failed"
      end
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::Serde::SerializationError, caught)
    assert_equal("the encoder refused the value", caught.cause.message)
  end
end
