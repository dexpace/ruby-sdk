# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"

# HTTP-38, HTTP-46, BODY-1, BODY-35.
class DexpaceFormBodyTest < DexpaceTestCase
  def drain(body)
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)
    sink.snapshot
  end

  test "is always replayable, which HTTP-38 states outright" do
    assert_predicate(Dexpace::Body.form([%w[a b]]), :replayable?)
  end

  test "carries the x-www-form-urlencoded media type" do
    assert_equal("application/x-www-form-urlencoded",
                 Dexpace::Body.form([%w[a b]]).media_type.render,)
  end

  # The whole reason the form encoder is a different function with a different name: "+" for space,
  # never "%20". A body that used the RFC 3986 encoder would be wrong in a way no test of either
  # function alone would catch.
  test "encodes a space as + and never as %20" do
    assert_equal("a+b=c+d".b, drain(Dexpace::Body.form([["a b", "c d"]])))
  end

  test "encodes a literal + as %2B, so a + in the output is unambiguously a space" do
    assert_equal("a=%2B".b, drain(Dexpace::Body.form([["a", "+"]])))
  end

  test "joins pairs with & and separates each name from its value with =" do
    assert_equal("a=1&b=2".b, drain(Dexpace::Body.form([%w[a 1], %w[b 2]])))
  end

  test "accepts a Hash as well as an Array of pairs" do
    assert_equal("a=1&b=2".b, drain(Dexpace::Body.form({ "a" => "1", "b" => "2" })))
  end

  test "reports the exact encoded byte count, not the source character count" do
    assert_equal("a=%C3%A9".b.bytesize, Dexpace::Body.form([%w[a é]]).content_length)
  end

  test "writes the same bytes every time, tagged BINARY" do
    body = Dexpace::Body.form([["a b", "é"]])

    assert_equal(drain(body), drain(body))
    assert_equal(::Encoding::BINARY, drain(body).encoding)
  end

  # The bytes are encoded at construction, so a drain-only assertion passes even when the pairs
  # are aliased: #pairs is public and folds into #== and #hash, so the copy has to be asserted on
  # the accessor itself (HTTP-5, XCUT-15).
  test "takes an independent frozen copy of the pairs at construction" do
    pair = [+"a", +"1"]
    source = [pair]
    body = Dexpace::Body.form(source)
    source << %w[b 2]
    pair[1] << "9"

    assert_equal([%w[a 1]], body.pairs)
    assert_predicate(body.pairs, :frozen?)
    assert_equal("a=1".b, drain(body))
  end

  test "rejects something that cannot be mapped over" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.form(42) }

    assert_includes(error.message, "Integer")
  end

  test "is frozen, so nothing can mutate it after construction" do
    assert_predicate(Dexpace::Body.form([%w[a 1]]), :frozen?)
  end

  test "has no readable source, because it is a request body" do
    assert_raises(Dexpace::StreamError) { Dexpace::Body.form([%w[a 1]]).source }
  end

  test "compares by value over its pairs" do
    assert_equal(Dexpace::Body.form([%w[a 1]]), Dexpace::Body.form([%w[a 1]]))
    refute_equal(Dexpace::Body.form([%w[a 1]]), Dexpace::Body.form([%w[a 2]]))
    assert_equal(Dexpace::Body.form([%w[a 1]]).hash, Dexpace::Body.form([%w[a 1]]).hash)
  end
end
