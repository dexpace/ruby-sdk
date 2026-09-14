# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-4, HTTP-47, SEAM-29. The shape is the point: XCUT-4 requires a transport error to be in
# Ruby's IOError family, so the SDK root cannot be a base class (design §5 addendum A3).
class DexpaceInvalidArgumentErrorTest < DexpaceTestCase
  test "is an ArgumentError, so a caller's existing rescue keeps matching" do
    assert_operator(Dexpace::InvalidArgumentError, :<, ::ArgumentError)
  end

  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::InvalidArgumentError, "url is required"
    rescue Dexpace::Error => error
      error
    end

    assert_equal("url is required", caught.message)
  end

  # The string form of module_eval, not the block form: only the string form sets the cref, so
  # only it puts the rescue in Dexpace's lexical scope, which is where a Dexpace::ArgumentError
  # would shadow ::ArgumentError. The block form keeps this file's scope and proves nothing --
  # verified by defining Dexpace::ArgumentError and watching this test error.
  test "a bare rescue ArgumentError inside the Dexpace namespace still catches Ruby's own" do
    caught = Dexpace.module_eval(<<~RUBY, __FILE__, __LINE__ + 1)
      begin
        Integer("not a number")
      rescue ArgumentError => error
        error
      end
    RUBY

    assert_instance_of(::ArgumentError, caught)
  end
end
