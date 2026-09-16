# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require_relative "../support/fake_context"

# CTX-9, CTX-10, CTX-18: #close is `store.release(self)`, and every clause of all three is a
# property of the store, not of Context itself. The private construction validation every
# flavour's #initialize runs is driven here through an includer shaped exactly like the three.
class DexpaceContextTest < DexpaceTestCase
  # The minimal store double: an object answering #set and #release, which is the whole of what a
  # context asks of its store (api-design/88e6bf12, the narrowest duck type).
  class FakeStore
    attr_accessor :released_with

    def set(context) = context

    def release(context)
      self.released_with = context
      context
    end
  end

  # A Data includer in the flavours' own shape -- the validation before `super` -- so the private
  # #validate_context! is exercised the way DispatchContext, RequestContext and ExchangeContext
  # exercise it, and stays off the public surface.
  class ProbeContext < Data.define(:bundle, :call_key, :store)
    include Dexpace::Context

    def initialize(bundle:, call_key:, store:)
      validate_context!(bundle: bundle, call_key: call_key, store: store)

      super
    end
  end

  test "#close delegates to store.release(self)" do
    store = FakeStore.new
    ctx = FakeContext.new(call_key: "k", store: store)

    assert_same(ctx, ctx.close)
    assert_same(ctx, store.released_with)
  end

  test "#close returns what the store returned, so CTX-10's no-op is observable" do
    store = FakeStore.new
    store.define_singleton_method(:release) { |_context| false }
    ctx = FakeContext.new(call_key: "k", store: store)

    refute(ctx.close)
  end

  test "the validation requires a non-nil bundle, with SEAM-29's one message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      ProbeContext.new(bundle: nil, call_key: "k", store: FakeStore.new)
    end

    assert_equal("bundle is required", error.message)
  end

  test "the validation requires a non-nil, non-empty call_key" do
    store = FakeStore.new

    error = assert_raises(Dexpace::InvalidArgumentError) do
      ProbeContext.new(bundle: :b, call_key: nil, store: store)
    end
    assert_equal("call_key is required", error.message)

    assert_raises(Dexpace::InvalidArgumentError) do
      ProbeContext.new(bundle: :b, call_key: "", store: store)
    end
  end

  # CTX-4's key is a String. A Symbol is refused rather than silently keying a slot that no String
  # lookup finds, and an Integer meets the SDK's error rather than a NoMethodError from #empty?.
  test "the validation requires the call_key to be a String, with the field-named message" do
    store = FakeStore.new

    [:sym, 5].each do |key|
      error = assert_raises(Dexpace::InvalidArgumentError, key.inspect) do
        ProbeContext.new(bundle: :b, call_key: key, store: store)
      end

      assert_equal("call_key must be a String", error.message, key.inspect)
    end
  end

  test "the validation requires a store that responds to #set and #release" do
    bad_store = Object.new
    only_set = Object.new.tap { |o| o.define_singleton_method(:set) { |c| c } }

    assert_raises(Dexpace::InvalidArgumentError) do
      ProbeContext.new(bundle: :b, call_key: "k", store: bad_store)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      ProbeContext.new(bundle: :b, call_key: "k", store: only_set)
    end
  end

  test "the validation passes for a store responding to both, and the instance is frozen" do
    ctx = ProbeContext.new(bundle: :b, call_key: "k", store: FakeStore.new)

    assert_equal("k", ctx.call_key)
    assert_predicate(ctx, :frozen?)
  end

  # The design gives Context exactly one public method, #close (P4-11); the validation is
  # private and takes no surface-manifest row.
  test "Context's public surface is #close alone" do
    assert_equal([:close], Dexpace::Context.public_instance_methods(false))
    assert_includes(Dexpace::Context.private_instance_methods(false), :validate_context!)
    assert_includes(Dexpace::Context.private_instance_methods(false), :validate_operation_name!)
    assert_empty(Dexpace::Context.singleton_methods)
  end

  # The module includes Dexpace::Model, so every flavour gets the validating #with by inclusion
  # (P1-4) -- the two-level ancestry verified fact 14 rests on.
  test "Context includes Dexpace::Model, so an includer's #with is Model's" do
    assert_includes(Dexpace::Context.ancestors, Dexpace::Model)
    assert_equal(Dexpace::Model, FakeContext.instance_method(:with).owner)
    assert_equal(Dexpace::Model, ProbeContext.instance_method(:with).owner)
  end
end
