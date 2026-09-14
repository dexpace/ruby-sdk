# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-10, HTTP-11, HTTP-12.
class DexpaceStatusTest < DexpaceTestCase
  test "maps a recognised code to a status carrying its canonical name" do
    assert_equal("OK", Dexpace::Status.of(200).canonical_name)
    assert_equal("Not Found", Dexpace::Status.canonical_name(404))
  end

  test "maps a vendor code without raising and without a name" do
    [499, 520, 526, 530, 599].each do |code|
      status = Dexpace::Status.of(code)

      assert_equal(code, status.code)
      assert_nil(status.canonical_name)
      assert_nil(Dexpace::Status.canonical_name(code))
    end
  end

  test "is equal to the canonical constant for the same code and hashes identically" do
    status = Dexpace::Status.of(200)

    assert_equal(Dexpace::Status::OK, status)
    assert_equal(Dexpace::Status::OK.hash, status.hash)
    refute_equal(Dexpace::Status::OK, Dexpace::Status::CREATED)
  end

  test "of is idempotent on a Status" do
    assert_same(Dexpace::Status::OK, Dexpace::Status.of(Dexpace::Status::OK))
  end

  test "classifies by range" do
    assert_predicate(Dexpace::Status.of(100), :informational?)
    assert_predicate(Dexpace::Status.of(204), :success?)
    assert_predicate(Dexpace::Status.of(301), :redirect?)
    assert_predicate(Dexpace::Status.of(404), :client_error?)
    assert_predicate(Dexpace::Status.of(503), :server_error?)
    refute_predicate(Dexpace::Status.of(204), :redirect?)
  end

  test "treats 400 through 599 as errors and nothing else" do
    assert_predicate(Dexpace::Status.of(400), :error?)
    assert_predicate(Dexpace::Status.of(599), :error?)
    refute_predicate(Dexpace::Status.of(399), :error?)
  end

  test "rejects a code outside the protocol's range as a caller mistake" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Status.of(99) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Status.of(600) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Status.of("200") }
  end

  test "requires a code, naming the field" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Status.of(nil) }

    assert_equal("code is required", error.message)
  end

  test "with re-validates, so a derived status cannot carry a nil code" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Status::OK.with(code: nil) }
    assert_equal(Dexpace::Status::NOT_FOUND, Dexpace::Status::OK.with(code: 404))
  end

  # HTTP-10's totality as a property rather than five examples.
  test "construction is total over the protocol's range" do
    sample(count: 256) do |rng|
      code = rng.rand(100..599)

      assert_equal(code, Dexpace::Status.of(code).code)
    end
  end
end
