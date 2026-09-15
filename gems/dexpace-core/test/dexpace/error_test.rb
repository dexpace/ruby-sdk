# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# HTTP-4, SEAM-29; XCUT-4 is what forces the shape. Dexpace::Error is a module, not a base
# class, so that a later transport error can subclass ::IOError and still be rescued as an SDK
# error (design §5 addendum A3, deviation P1-2).
class DexpaceErrorTest < DexpaceTestCase
  test "the error root is a module, not a class" do
    assert_kind_of(Module, Dexpace::Error)
    refute_kind_of(Class, Dexpace::Error)
  end

  # The shadowing name this SDK never defines: it would make a bare `rescue ArgumentError` inside
  # `module Dexpace` stop catching Ruby's own (deviation P1-3).
  test "never defines Dexpace::ArgumentError" do
    refute_includes(Dexpace.constants(false), :ArgumentError)
  end
end
