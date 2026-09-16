# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# R8, P4-24, P4-25: the pure transform contract 4c's generic adapter consumes and the three
# shipped steps implement. #phase and #apply are declared; #call is the module's ONE default
# implementation, which is what makes a transform a recovery-chain step with no adapter.
class DexpaceRecoveryTransformTest < DexpaceTestCase
  # A transform over Strings: the contract is about the shape, and a String is the cheapest
  # value that has an obvious transform.
  class Upcasing
    include Dexpace::Recovery::Transform

    def phase = :request

    def apply(value) = value.upcase
  end

  test "a transform declares its phase and applies as a pure function of its argument" do
    transform = Upcasing.new

    assert_equal(:request, transform.phase)
    assert_equal("INPUT", transform.apply("input"))
    assert_kind_of(Dexpace::Recovery::Transform, transform)
  end

  # R8 clause 4: installed into a chain as itself, by the chain's one-argument #call protocol.
  test "call forwards to apply, so a transform is a chain step without an adapter (P4-25)" do
    transform = Upcasing.new

    assert_equal("INPUT", transform.call("input"))
    assert_equal(%i[apply call phase],
                 Dexpace::Recovery::Transform.public_instance_methods(false).sort,)
  end

  # NotImplementedError is a ScriptError: an includer that forgot a declared method is a
  # programmer error and escapes every StandardError rescue, the same rule as Closeable#release.
  test "the declared methods raise NotImplementedError naming the includer until implemented" do
    bare = Object.new.extend(Dexpace::Recovery::Transform)

    phase = assert_raises(::NotImplementedError) { bare.phase }
    apply = assert_raises(::NotImplementedError) { bare.apply("value") }

    assert_match(/Object#phase/, phase.message)
    assert_match(/Object#apply/, apply.message)
    assert_raises(::NotImplementedError) { bare.call("value") }
  end
end
