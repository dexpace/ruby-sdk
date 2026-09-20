# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# SERDE-13, SERDE-21, SERDE-22. The strictness burden moves into the witness (serde/b5e5efc8) --
# which makes it a per-field discipline unless something makes it a shared helper. This is that
# helper, and it is Model.required!'s discipline applied to a second family of failures: ONE raise
# site, ONE message form, so "naming the target type" is a property of one method rather than of
# every witness anyone writes. Split under Metrics/ClassLength: the value and its path, then the
# nine refusals and two permissions, then the one raise site.
class DexpaceSerdeDecodeContextTest < DexpaceTestCase
  DC = Dexpace::Serde::DecodeContext

  # The root context every nested case starts from.
  module Fixtures
    def ctx = DC.root
  end

  # The value: construction, the path, the target name.
  class ValueTest < DexpaceTestCase
    include Fixtures

    test "the root context has an empty frozen path and is itself frozen" do
      assert_empty(ctx.path)
      assert_predicate(ctx.path, :frozen?)
      assert_predicate(ctx, :frozen?)
      assert_nil(ctx.target)
      assert_same(ctx, DC.root, "the no-target root is one shared instance")
    end

    test ".root takes a class, a module, a String or an instance and stores a NAME" do
      assert_equal("String", DC.root(target: ::String).target)
      assert_predicate(DC.root(target: ::String).target, :frozen?)
      assert_equal("Comparable", DC.root(target: ::Comparable).target)
      assert_equal("Pet", DC.root(target: "Pet").target)
      combinator = Object.new
      def combinator.dexpace_load(parsed, _ctx) = parsed

      assert_equal("Object", DC.root(target: combinator).target)
      assert_nil(DC.root(target: Class.new).target, "an anonymous class has no name to carry")
    end

    test "#at appends one segment and returns a new context, leaving the receiver untouched" do
      child = ctx.at("pets").at(3).at("name")

      assert_equal(["pets", 3, "name"], child.path)
      assert_predicate(child.path, :frozen?)
      assert_empty(ctx.path)
    end

    test "#at carries the target and refuses a segment that is neither a String nor an Integer" do
      assert_equal("Pet", DC.root(target: "Pet").at("tags").target)
      error = assert_raises(Dexpace::InvalidArgumentError) { ctx.at(:name) }

      assert_match(/segment/, error.message)
    end

    # The construction pattern holds: .new and .[] are private, .build validates, #with
    # re-validates.
    test "follows the construction pattern: private constructors, a validating .build, #with" do
      refute_respond_to(DC, :new)
      refute_respond_to(DC, :[])
      assert_equal(["a"], DC.build(path: ["a"], target: nil).path)
      assert_equal("Pet", DC.build(path: [], target: nil).with(target: "Pet").target)
      assert_raises(Dexpace::InvalidArgumentError) { DC.build(path: nil, target: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { DC.build(path: [:a], target: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { DC.build(path: [], target: 5) }
    end

    test "#path is the model's own frozen copy, never the caller's array" do
      segments = ["a"]
      context = DC.build(path: segments, target: nil)
      segments << "b"

      assert_equal(["a"], context.path)
    end

    test "the path renders as an RFC 6901 pointer with ~0 and ~1 escaping" do
      assert_equal("/a~1b/c~0d", ctx.at("a/b").at("c~d").pointer)
      assert_equal("/pets/0/name", ctx.at("pets").at(0).at("name").pointer)
      assert_equal("", ctx.pointer, "RFC 6901: the whole document is the empty pointer")
    end
  end

  # SERDE-21: the nine named cross-shape coercions, one fixture each -- a loop would hide a dropped
  # case, and the requirement enumerates them individually. SERDE-22: the two permissions.
  class CoercionTest < DexpaceTestCase
    include Fixtures

    test "SERDE-21: string to integer is rejected" do
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.integer!("5") }
    end

    test "SERDE-21: string to float is rejected" do
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.float!("1.5") }
    end

    test "SERDE-21: string to boolean is rejected" do
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.boolean!("true") }
    end

    test "SERDE-21: empty string to integer, float and boolean are all rejected" do
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.integer!("") }
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.float!("") }
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.boolean!("") }
    end

    test "SERDE-21: float to integer is rejected (lossy narrowing)" do
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.integer!(1.5) }
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.integer!(1.0) }
    end

    test "SERDE-21: boolean to integer and integer to boolean are both rejected" do
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.integer!(true) }
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.boolean!(1) }
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.boolean!(0) }
    end

    test "SERDE-21: boolean to float is rejected" do
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.float!(true) }
    end

    test "SERDE-21: a non-string scalar to string is rejected" do
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.string!(5) }
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.string!(true) }
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.string!(1.5) }
    end

    # An implementation that rejects these has broken a MUST while looking stricter and therefore
    # more correct.
    test "SERDE-22: an integer widens into a float target" do
      widened = ctx.float!(1)

      assert_in_delta(1.0, widened)
      assert_instance_of(::Float, widened)
      assert_in_delta(1.5, ctx.float!(1.5))
    end

    test "SERDE-22: an empty string binds to a textual target" do
      assert_equal("", ctx.string!(""))
    end

    test "SERDE-22: every well-typed value binds to its matching target unchanged" do
      assert_equal(5, ctx.integer!(5))
      assert_equal("é", ctx.string!("é"))
      assert(ctx.boolean!(true))
      refute(ctx.boolean!(false))
    end

    test "#object! and #array! reject the wrong container and accept the right one" do
      assert_equal({ "a" => 1 }, ctx.object!({ "a" => 1 }))
      assert_equal([1], ctx.array!([1]))
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.object!([]) }
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.array!({}) }
      assert_raises(Dexpace::Serde::DeserializationError) { ctx.array!(nil) }
    end
  end

  # SERDE-13: the one raise site, and its message form.
  class RaiseSiteTest < DexpaceTestCase
    include Fixtures

    # SERDE-13's conformance clause decodes "the literal null into a non-null DTO" and asserts the
    # message names THE TARGET TYPE. A witness reached with nil calls ctx.object!(nil), which knows
    # only the shape it wanted -- so without a target on the root frame the message names Hash where
    # the requirement asks for Pet. The target is carried by #at but only RENDERED at the root,
    # because a nested frame's target IS its expected shape.
    test "SERDE-13: the root frame names the target type, and a nested frame does not" do
      root = DC.root(target: "Pet")

      at_root = assert_raises(Dexpace::Serde::DeserializationError) { root.object!(nil) }
      nested  = assert_raises(Dexpace::Serde::DeserializationError) { root.at("tags").string!(nil) }

      assert_equal("expected Pet (Hash) at /, got NilClass", at_root.message)
      assert_equal("expected String at /tags, got NilClass", nested.message)
    end

    test "SERDE-13: a wire null into a non-null target names the target type and the path" do
      error = assert_raises(Dexpace::Serde::DeserializationError) do
        ctx.at("pets").at(0).string!(nil, key: "name")
      end

      assert_equal("expected String at /pets/0/name, got NilClass", error.message)
    end

    test "key: appends one segment for the message only and leaves the receiver's path alone" do
      context = ctx.at("pet")
      error = assert_raises(Dexpace::Serde::DeserializationError) do
        context.integer!("x", key: "id")
      end

      assert_match(%r{ at /pet/id,}, error.message)
      assert_equal(["pet"], context.path)
    end

    test "the message renders the escaped pointer" do
      error = assert_raises(Dexpace::Serde::DeserializationError) do
        ctx.at("a/b").at("c~d").string!(1)
      end

      assert_equal("expected String at /a~1b/c~0d, got Integer", error.message)
    end

    test "#present! rejects nil and names the caller's target; false is a present value" do
      assert_equal(5, ctx.present!(5, "Pet"))
      assert_same(false, ctx.present!(false, "Flag"))

      error = assert_raises(Dexpace::Serde::DeserializationError) { ctx.present!(nil, "Pet") }

      assert_equal("expected Pet at /, got NilClass", error.message)
    end

    test "#present! at a root frame whose target is the same name does not name it twice" do
      error = assert_raises(Dexpace::Serde::DeserializationError) do
        DC.root(target: "Pet").present!(nil, "Pet")
      end

      assert_equal("expected Pet at /, got NilClass", error.message)
    end

    test "#error! is the one raise site and its error is the seam's decode subtype" do
      error = assert_raises(Dexpace::Serde::DeserializationError) do
        ctx.error!(expected: "Thing", actual: 5, key: "k")
      end

      assert_kind_of(Dexpace::Serde::Error, error)
      assert_kind_of(Dexpace::Error, error)
      assert_equal("expected Thing at /k, got Integer", error.message)
    end
  end
end
