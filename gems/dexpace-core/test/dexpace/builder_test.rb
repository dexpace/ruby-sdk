# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# SEAM-29's second MUST: a shared generic Builder contract, so a generic composition helper can
# accept any builder. The five-entry list in the first test IS the requirement's conformance step.
class DexpaceBuilderTest < DexpaceTestCase
  class Incomplete
    include Dexpace::Builder
  end

  # The conformance step: "a builder is assignable where the generic Builder contract is
  # expected", for all five builders this phase ships.
  test "a generic helper accepts every builder in the phase" do
    request = Dexpace::Request.builder
    request.url = "https://example.test/"
    response = Dexpace::Response.builder
    response.request = request.build
    response.protocol = "http/1.1"
    response.status = 200
    builders = [
      Dexpace::Headers.builder, Dexpace::Query.builder, Dexpace::RequestOptions.builder, request,
      response,
    ]

    expected = [
      Dexpace::Headers, Dexpace::Query, Dexpace::RequestOptions, Dexpace::Request,
      Dexpace::Response,
    ]

    assert_equal(expected, Dexpace::Builder.build_all(builders).map(&:class))
  end

  test "a builder that does not implement build fails loudly rather than silently" do
    assert_raises(NotImplementedError) { Incomplete.new.build }
  end

  test "the generic helper rejects an object that is not a builder" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Builder.build_all([Object.new])
    end

    assert_includes(error.message, "Object")
  end
end
