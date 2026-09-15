# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# HTTP-3, HTTP-4, HTTP-5, SEAM-29, XCUT-15. The #with case is the one that matters: Data#with does
# NOT call an initialize override on Ruby 3.2 (verified against 3.2.11, 3.4.10 and 4.0.6), so
# without this module derivation is unvalidated on the declared floor and validated everywhere
# else. Design §4 addendum A1.
class DexpaceModelTest < DexpaceTestCase
  # A minimal type in the shape every core model uses: private new, validating build, Model
  # included. Defined here rather than in lib/ because it exists only to test the contract.
  class Sample < Data.define(:code)
    include Dexpace::Model

    private_class_method :new

    def self.build(code:)
      new(code: code)
    end

    def initialize(code:)
      Dexpace::Model.required!("code", code)
      super
    end
  end

  test "required! raises the one error class with SEAM-29's message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Model.required!("url", nil) }

    assert_equal("url is required", error.message)
  end

  test "required! returns the value when it is present" do
    assert_equal(200, Dexpace::Model.required!("code", 200))
  end

  test "with re-validates on every supported Ruby" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Sample.build(code: 1).with(code: nil) }

    assert_equal("code is required", error.message)
  end

  test "with returns the receiver when nothing changes" do
    sample = Sample.build(code: 1)

    assert_same(sample, sample.with)
    assert_same(sample, sample.with({}))
  end

  # The positional form (checklist deviation 1) admits any object where the keyword form would
  # have raised ArgumentError at the call site; a non-Hash is the SDK's error, never a
  # NoMethodError from reading `empty?` off it.
  test "with refuses a positional argument that is not a Hash with the SDK's error" do
    sample = Sample.build(code: 1)

    assert_raises(Dexpace::InvalidArgumentError) { sample.with(5) }
    assert_raises(Dexpace::InvalidArgumentError) { sample.with([[:code, 2]]) }
  end

  test "with produces a new validated instance when something changes" do
    derived = Sample.build(code: 1).with(code: 2)

    assert_equal(2, derived.code)
    assert_predicate(derived, :frozen?)
  end

  test "own returns a deep-frozen copy and leaves the caller's collection alone" do
    source = { "accept" => ["application/json"] }
    owned = Dexpace::Model.own(source)

    assert_predicate(owned, :frozen?)
    assert_predicate(owned.fetch("accept"), :frozen?)
    refute_predicate(source, :frozen?)
    refute_predicate(source.fetch("accept"), :frozen?)
  end

  test "own produces a Ractor-shareable value, which proves the freeze reached every level" do
    assert(Ractor.shareable?(Dexpace::Model.own({ "accept" => ["application/json"] })))
  end

  test "a model built from a live hash does not change when the caller mutates it afterwards" do
    source = { "accept" => ["application/json"] }
    owned = Dexpace::Model.own(source)
    source["accept"] << "text/plain"

    assert_equal(["application/json"], owned.fetch("accept"))
  end

  # XCUT-15: a String the caller still holds is externally-mutable state a model must not alias.
  test "frozen_string returns a frozen copy of a mutable string and the same frozen string" do
    mutable = +"Accept"
    copy = Dexpace::Model.frozen_string(mutable)
    mutable << "-Language"

    assert_equal("Accept", copy)
    assert_predicate(copy, :frozen?)
    already = "Accept"

    assert_same(already, Dexpace::Model.frozen_string(already))
  end
end
