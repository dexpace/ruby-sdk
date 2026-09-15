# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-34, HTTP-35, HTTP-3, HTTP-5, XCUT-15. These are operational overrides and are deliberately
# NOT part of the wire model (HTTP-6), which is why they are a separate type rather than members
# of Request.
class DexpaceRequestOptionsTest < DexpaceTestCase
  test "EMPTY overrides nothing" do
    empty = Dexpace::RequestOptions::EMPTY

    assert_nil(empty.timeout)
    assert_nil(empty.max_retries)
    assert_empty(empty.tags)
    assert_predicate(empty.tags, :frozen?)
  end

  test "EMPTY is one shared frozen instance, so overriding nothing allocates nothing" do
    assert_same(Dexpace::RequestOptions::EMPTY, Dexpace::RequestOptions::EMPTY)
    assert_predicate(Dexpace::RequestOptions::EMPTY, :frozen?)
    assert(Ractor.shareable?(Dexpace::RequestOptions::EMPTY))
  end

  test "tags are copied at build, so later mutation of the source map cannot reach the model" do
    source = { "tenant" => +"acme" }
    options = Dexpace::RequestOptions.build(timeout: nil, max_retries: nil, tags: source)
    source["tenant"] << "-2"
    source["other"] = "x"

    assert_equal({ "tenant" => "acme" }, options.tags)
    assert_same(options.tags, options.tags)
    refute_predicate(source, :frozen?)
  end

  test "rejects a zero or negative timeout, because zero means no timeout in one transport" do
    [0, 0.0, -1.5].each do |timeout|
      builder = Dexpace::RequestOptions.builder
      builder.timeout = timeout

      assert_raises(Dexpace::InvalidArgumentError, timeout.to_s) { builder.build }
    end
  end

  test "accepts a nil timeout, which is the use-the-default sentinel" do
    assert_nil(Dexpace::RequestOptions.builder.build.timeout)
  end

  # A Complex is a Numeric with no #positive?, so it would escape as a NoMethodError from inside
  # the check; an infinite or NaN timeout is a positive-looking value no socket API can take.
  # All three are the caller's mistake and the SDK's error reports them (the Task 1 rule).
  test "rejects a timeout that is not a finite real number with the SDK's error" do
    [Complex(1, 0), Float::INFINITY, Float::NAN].each do |timeout|
      assert_raises(Dexpace::InvalidArgumentError, timeout.to_s) do
        Dexpace::RequestOptions.build(timeout: timeout, max_retries: nil, tags: {})
      end
    end
    rational = Dexpace::RequestOptions.build(timeout: 3r / 2, max_retries: nil, tags: {})

    assert_in_delta(1.5, rational.timeout)
  end

  test "holds the timeout as a Float of seconds, whatever numeric it was given" do
    builder = Dexpace::RequestOptions.builder
    builder.timeout = 2

    assert_in_delta(2.0, builder.build.timeout)
    assert_instance_of(Float, builder.build.timeout)
    assert_raises(Dexpace::InvalidArgumentError) { builder.timeout = "2" }
  end

  test "with re-validates, so a derived options cannot carry a zero timeout" do
    options = Dexpace::RequestOptions.build(timeout: 2.5, max_retries: nil, tags: {})

    assert_raises(Dexpace::InvalidArgumentError) { options.with(timeout: 0) }
    assert_raises(Dexpace::InvalidArgumentError) { options.with(max_retries: -1) }
    assert_equal(3, options.with(max_retries: 3).max_retries)
  end

  test "rejects a negative max-retries and accepts zero, which disables retries for this call" do
    negative = Dexpace::RequestOptions.builder
    negative.max_retries = -1

    assert_raises(Dexpace::InvalidArgumentError) { negative.build }

    zero = Dexpace::RequestOptions.builder
    zero.max_retries = 0

    assert_equal(0, zero.build.max_retries)
    assert_raises(Dexpace::InvalidArgumentError) { zero.max_retries = 1.5 }
  end

  test "build rejects tags that are not a map of Strings to Strings" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::RequestOptions.build(timeout: nil, max_retries: nil, tags: { tenant: "acme" })
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::RequestOptions.build(timeout: nil, max_retries: nil, tags: { "tenant" => 1 })
    end
    # A non-copyable object, as the map or as a value, is refused before anything is copied, so
    # the stdlib's TypeError from Ractor.make_shareable never escapes `rescue Dexpace::Error`.
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::RequestOptions.build(timeout: nil, max_retries: nil, tags: -> {})
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::RequestOptions.build(timeout: nil, max_retries: nil, tags: { "t" => Thread.current })
    end
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::RequestOptions.build(timeout: nil, max_retries: nil, tags: nil)
    end

    assert_equal("tags is required", error.message)
  end

  test "new_builder is pre-filled and does not alias the model's tags" do
    options = Dexpace::RequestOptions.build(timeout: 1.5, max_retries: 2, tags: { "a" => "1" })
    derived = options.new_builder.tag("b", "2").build

    assert_in_delta(1.5, derived.timeout)
    assert_equal(2, derived.max_retries)
    assert_equal({ "a" => "1", "b" => "2" }, derived.tags)
    assert_equal({ "a" => "1" }, options.tags)
  end
end
