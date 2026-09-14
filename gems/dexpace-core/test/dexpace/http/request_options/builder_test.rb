# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"

# HTTP-34, HTTP-35, SEAM-29.
class DexpaceRequestOptionsBuilderTest < DexpaceTestCase
  test "builds the empty options when nothing is set" do
    assert_equal(Dexpace::RequestOptions::EMPTY, Dexpace::RequestOptions.builder.build)
  end

  test "sets a timeout, a max-retries and tags" do
    builder = Dexpace::RequestOptions.builder
    builder.timeout = 1.5
    builder.max_retries = 3
    options = builder.tag("tenant", "acme").tag("region", "eu").build

    assert_in_delta(1.5, options.timeout)
    assert_equal(3, options.max_retries)
    assert_equal({ "tenant" => "acme", "region" => "eu" }, options.tags)
  end

  test "a later tag under the same key replaces the earlier one, and nil clears a field" do
    builder = Dexpace::RequestOptions.builder
    builder.timeout = 1.5
    builder.timeout = nil
    options = builder.tag("tenant", "acme").tag("tenant", "other").build

    assert_nil(options.timeout)
    assert_equal({ "tenant" => "other" }, options.tags)
  end

  test "a tag key and value must be Strings, and a rejected tag leaves no partial state" do
    builder = Dexpace::RequestOptions.builder.tag("a", "1")

    assert_raises(Dexpace::InvalidArgumentError) { builder.tag(:b, "2") }
    assert_raises(Dexpace::InvalidArgumentError) { builder.tag("b", 2) }
    assert_equal({ "a" => "1" }, builder.build.tags)
  end

  test "building twice yields two independent models" do
    builder = Dexpace::RequestOptions.builder.tag("a", "1")
    first = builder.build
    builder.tag("b", "2")

    assert_equal({ "a" => "1" }, first.tags)
    assert_equal({ "a" => "1", "b" => "2" }, builder.build.tags)
  end

  test "implements the shared builder contract" do
    assert_kind_of(Dexpace::Builder, Dexpace::RequestOptions.builder)
  end
end
