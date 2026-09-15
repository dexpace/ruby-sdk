# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# SEAM-26. A frozen Data descriptor: an HTTP method, a path template with named placeholders, and
# typed projections of inputs onto path / query / header / body. Only method and template are
# required and the four projections default to empty, so "a parameterless GET overriding only
# method+path" is the default construction.
#
# Two placeholder checks at two times, which is what makes SEAM-27's "every placeholder MUST have a
# supplied value" structural rather than a runtime hope: at construction the set of :path
# projection names must equal the set of {name} placeholders, and at #build_request every projected
# path input must have a value.
class DexpaceOperationTest < DexpaceTestCase
  test "a parameterless operation needs only a method and a template" do
    operation = Dexpace::Operation.build(method: "GET", template: "/pets")

    assert_equal(Dexpace::Method.of("GET"), operation.method)
    assert_equal("/pets", operation.template)
    assert_empty(operation.projections)
    assert_empty(operation.placeholders)
  end

  test "the method is coerced through Method.of, so a String never survives as a member" do
    operation = Dexpace::Operation.build(method: "post", template: "/pets")

    assert_instance_of(Dexpace::Method, operation.method)
    assert_equal("POST", operation.method.to_s)
    typed = Dexpace::Operation.build(method: Dexpace::Method::GET, template: "/x")

    assert_same(Dexpace::Method::GET, typed.method)
  end

  test "a missing required field fails with SEAM-29's message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: nil)
    end

    assert_equal("template is required", error.message)

    method_error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: nil, template: "/pets")
    end

    assert_equal("method is required", method_error.message)
  end

  test "an empty template is legal, because SEAM-27 says an empty path leaves the base untouched" do
    operation = Dexpace::Operation.build(method: "GET", template: "")

    assert_equal("", operation.template)
  end

  test "a template must be a String" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: :pets)
    end

    assert_match(/template must be a String/, error.message)
  end

  test "placeholders are read off the template, in order, and placeholders_in is public" do
    operation = Dexpace::Operation.build(
      method: "GET", template: "/owners/{owner}/pets/{id}",
      projections: { owner: [:path, "owner"], id: [:path, "id"] },
    )

    assert_equal(%w[owner id], operation.placeholders)
    assert_equal(%w[a b], Dexpace::Operation.placeholders_in("/{a}/{b}"))
    assert_empty(Dexpace::Operation.placeholders_in("/none"))
  end

  test "every template placeholder must have a path projection" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: "/pets/{id}")
    end

    assert_match(/"id"/, error.message)
    assert_match(/no path projection/, error.message)
  end

  test "a path projection naming no placeholder is refused" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(
        method: "GET", template: "/pets", projections: { id: [:path, "id"] },
      )
    end

    assert_match(/name no template placeholder/, error.message)
  end

  test "an unbalanced brace and an empty placeholder are refused" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: "/pets/{id")
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: "/pets/}")
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Operation.build(method: "GET", template: "/pets/{}")
    end
  end

  # Validation, from the projections table's side.
  class Projections < DexpaceTestCase
    test "a projection targeting something other than the four parts is refused, naming them" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Operation.build(
          method: "GET", template: "/pets", projections: { biscuit: [:cookie, "c"] },
        )
      end

      assert_match(/:path/, error.message)
      assert_match(/:cookie/, error.message)
    end

    test "a projection with no wire name is refused" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Operation.build(
          method: "GET", template: "/pets", projections: { tag: [:query, ""] },
        )
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Operation.build(
          method: "GET", template: "/pets", projections: { tag: [:query, nil] },
        )
      end
    end

    test "a projection that is not a [target, wire name] pair is refused" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Operation.build(method: "GET", template: "/pets", projections: { tag: :query })
      end
    end

    test "at most one body projection" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Operation.build(
          method: "POST", template: "/pets", projections: { a: [:body, "a"], b: [:body, "b"] },
        )
      end
    end

    test "projections must be a Hash, and the error names what was passed" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Operation.build(method: "GET", template: "/pets", projections: [[:query, "q"]])
      end

      assert_match(/Array/, error.message)
    end

    test "the descriptor is frozen and its projections are deep-frozen" do
      operation = Dexpace::Operation.build(
        method: "GET", template: "/pets", projections: { tag: [:query, "tag"] },
      )

      assert_predicate(operation, :frozen?)
      assert_predicate(operation.projections, :frozen?)
      assert_predicate(operation.projections[:tag], :frozen?)
      assert_predicate(operation.template, :frozen?)
      assert_raises(::FrozenError) { operation.projections[:other] = [:query, "other"] }
    end

    test "a caller's projections hash is copied, not aliased" do
      projections = { tag: [:query, "tag"] }
      operation = Dexpace::Operation.build(method: "GET", template: "/pets",
                                           projections: projections,)

      projections[:sneaky] = [:query, "sneaky"]

      assert_equal(%i[tag], operation.projections.keys,
                   "XCUT-15: the model holds no alias to externally mutable state",)
    end

    # Data#with does not call an initialize override on Ruby 3.2 (verified 3.2.11 / 3.4.10 /
    # 4.0.6), so without phase 1's shared #with this passes on 3.4 and 4.0 and skips validation on
    # the floor.
    test "with re-validates on every supported Ruby" do
      operation = Dexpace::Operation.build(method: "GET", template: "/pets")

      assert_raises(Dexpace::InvalidArgumentError) { operation.with(template: "/pets/{id}") }
      assert_equal("/other", operation.with(template: "/other").template)
    end

    test "new is private; .build is the construction path" do
      refute_respond_to(Dexpace::Operation, :new)
      assert_respond_to(Dexpace::Operation, :build)
    end
  end
end
