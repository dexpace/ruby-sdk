# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SEAM-23. A class root here, inverting phase 1's module root for the SDK-wide Dexpace::Error, and
# the inversion is deliberate (deviation P2-2): phase 1's root is a module because XCUT-4 puts
# transport errors in Ruby's IOError family and single inheritance makes a class root and that
# requirement mutually exclusive. No competing family exists here, because SEAM-20 and SEAM-21 both
# say a genuine stream I/O error propagates unwrapped rather than being reclassified.
class DexpaceSerdeErrorTest < DexpaceTestCase
  test "the hierarchy is a class root with encode and decode subtypes" do
    assert_operator(Dexpace::Serde::SerializationError, :<, Dexpace::Serde::Error)
    assert_operator(Dexpace::Serde::DeserializationError, :<, Dexpace::Serde::Error)
    assert_operator(Dexpace::Serde::Error, :<, ::StandardError)
  end

  test "every one is caught by rescue Dexpace::Error" do
    [Dexpace::Serde::Error,
     Dexpace::Serde::SerializationError,
     Dexpace::Serde::DeserializationError,].each do |klass|
      caught = begin
        raise klass, "boom"
      rescue Dexpace::Error => error
        error
      end

      assert_instance_of(klass, caught)
    end
  end

  test "a serde failure is not in Ruby's IOError family" do
    refute_operator(Dexpace::Serde::Error, :<, ::IOError,
                    "SEAM-20/SEAM-21: a genuine stream I/O error propagates unwrapped instead",)
  end

  test "the base type is open for an adapter to subclass" do
    subtype = Class.new(Dexpace::Serde::DeserializationError)

    caught = begin
      raise subtype, "vendor-specific"
    rescue Dexpace::Serde::Error => error
      error
    end

    assert_instance_of(subtype, caught)
  end

  # Adapters raise these from inside a rescue so Ruby sets #cause automatically, rather than
  # leaking the backing library's exception type (serde/5821286d). Stated at the seam here,
  # asserted per adapter in phases 7 and 8.
  test "raising from inside a rescue chains the original as the cause" do
    original = ::RuntimeError.new("the backing library said no")

    caught = begin
      begin
        raise original
      rescue ::RuntimeError
        raise Dexpace::Serde::DeserializationError, "decode failed"
      end
    rescue Dexpace::Serde::Error => error
      error
    end

    assert_same(original, caught.cause)
  end

  # Inside `module Dexpace::Serde` a bare `Error` is this class; the SDK root is reached only as
  # Dexpace::Error, fully qualified, which is what every core file writes.
  test "a bare Error inside the Serde namespace is the seam root, not the SDK root" do
    resolved = Dexpace::Serde.module_eval("Error", __FILE__, __LINE__)

    assert_same(Dexpace::Serde::Error, resolved)
    refute_same(Dexpace::Error, resolved)
  end
end
