# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SERDE-14, SERDE-18, SERDE-30. Three states and no fourth: Present is bounded to non-null so
# Present-of-null is unrepresentable through the public API. The module is included by all three
# values, exactly Outcome's shape (4b) and Context's (4a), so v.is_a?(Tristate) is one type test.
class DexpaceSerdeTristateTest < DexpaceTestCase
  T = Dexpace::Serde::Tristate

  test "all three values share the module, so one type test covers them" do
    assert_kind_of(T, T::ABSENT)
    assert_kind_of(T, T::NULL)
    assert_kind_of(T, T.present(1))
  end

  # SERDE-14: the illegal fourth state, closed on the CONSTRUCTION path.
  test "SERDE-14: Present rejects nil at construction" do
    error = assert_raises(Dexpace::InvalidArgumentError) { T.present(nil) }

    assert_equal("value is required", error.message)
    assert_raises(Dexpace::InvalidArgumentError) { T::Present.build(value: nil) }
  end

  # SERDE-14 on the two generated constructors: Data.define makes .new AND .[] and both are
  # private, so `Present[value: nil]` is not a fourth state either; the validation lives in
  # #initialize, so every construction path -- .build, and the send-past-private hole P8 records
  # -- passes through it.
  test "SERDE-14: .new and .[] are private, and #initialize validates for every path" do
    refute_respond_to(T::Present, :new)
    refute_respond_to(T::Present, :[])
    assert_raises(::NoMethodError) { T::Present[value: nil] }
    assert_raises(Dexpace::InvalidArgumentError) { T::Present.send(:new, value: nil) }
  end

  # SERDE-14: and closed on the DERIVATION path, which is the half a reader will not think to test.
  # Model#with routes through .build on every supported Ruby (data-modeling/83610619) -- Data#with
  # does NOT call an initialize override on 3.2, so without Model this would silently succeed there.
  test "SERDE-14: #with cannot derive a Present holding nil, on any supported Ruby" do
    assert_raises(Dexpace::InvalidArgumentError) { T.present(1).with(value: nil) }
    assert_equal(2, T.present(1).with(value: 2).value)
  end

  test "SERDE-18: the three factories" do
    assert_same(T::ABSENT, T.absent)
    assert_same(T::NULL, T.null)
    assert_equal(1, T.present(1).value)
    assert_same(false, T.present(false).value, "false is a value, not an absence")
  end

  # SERDE-18's own conformance clause, quoted: "assert the nullable mapper yields Present for
  # non-null and Null for null". It can NEVER yield Absent, which is why it is a separate name from
  # Tristate.of -- the combinator.
  test "SERDE-18: from_nullable yields Present or Null and never Absent" do
    assert_predicate(T.from_nullable(1), :present?)
    assert_equal(1, T.from_nullable(1).value)
    assert_predicate(T.from_nullable(nil), :null?)
    refute_predicate(T.from_nullable(nil), :absent?)
    assert_same(T::NULL, T.from_nullable(nil))
  end

  test "SERDE-18: the three predicates are exhaustive and mutually exclusive" do
    [T::ABSENT, T::NULL, T.present(1)].each do |value|
      assert_equal(1, [value.absent?, value.null?, value.present?].count(true), value.to_s)
    end
    assert_predicate(T::ABSENT, :absent?)
    assert_predicate(T::NULL, :null?)
    assert_predicate(T.present(1), :present?)
  end

  test "SERDE-18: the three-way fold" do
    fold = ->(v) { v.fold(on_absent: -> { :a }, on_null: -> { :n }, on_present: ->(x) { x }) }

    assert_equal(:a, fold.call(T::ABSENT))
    assert_equal(:n, fold.call(T::NULL))
    assert_equal(7, fold.call(T.present(7)))
  end

  test "SERDE-18: the value-or-null accessor" do
    assert_nil(T::ABSENT.value_or_nil)
    assert_nil(T::NULL.value_or_nil)
    assert_equal(7, T.present(7).value_or_nil)
  end

  # SERDE-30 (MAY, taken). Ruby's default #inspect for a singleton renders its object id, so a log
  # line or a test failure comparing tristates would otherwise differ between runs. Asserted as
  # string equality, not as refute_match(/0x/), because the requirement names the forms.
  test "SERDE-30: the sentinels have stable identity-free textual forms" do
    assert_equal("Absent", T::ABSENT.to_s)
    assert_equal("Absent", T::ABSENT.inspect)
    assert_equal("Null", T::NULL.to_s)
    assert_equal("Null", T::NULL.inspect)
  end

  test "the sentinels are frozen singletons of classes a caller cannot name" do
    assert_predicate(T::ABSENT, :frozen?)
    assert_predicate(T::NULL, :frozen?)
    assert_same(T::ABSENT, T.absent)
    refute_equal(T::ABSENT, T::NULL)
    refute_includes(T.constants(false), :Absent)
    refute_includes(T.constants(false), :Null)
  end

  test "Present compares by value and is frozen" do
    assert_equal(T.present(1), T.present(1))
    refute_equal(T.present(1), T.present(2))
    assert_predicate(T.present(1), :frozen?)
    assert_equal(T.present(1).hash, T.present(1).hash)
  end

  # The encode half every value answers (SERDE-15/SERDE-20, cashed in by Native): Absent dumps to
  # the OMIT sentinel the walk drops from a Hash, Null to nil, Present to its inner value.
  test "#dexpace_dump: OMIT for Absent, nil for Null, the inner value for Present" do
    assert_same(Dexpace::Serde::OMIT, T::ABSENT.dexpace_dump)
    assert_nil(T::NULL.dexpace_dump)
    assert_equal("v", T.present("v").dexpace_dump)
  end

  test "the module has no factory of its own for a Present holding nothing" do
    assert_equal(%i[absent from_nullable null of present].sort,
                 (T.singleton_methods - Module.instance_methods).sort,)
  end
end
