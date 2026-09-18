# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CFG-11: the two shipped seams and the hermetic constructor, each a frozen callable from key
# name to String?. P5-3: the environment seam is ENVIRONMENT, never ENV.
class DexpaceConfigurationSourcesTest < DexpaceTestCase
  test "CFG-11: ENVIRONMENT reads the process environment by exact name, nil when absent" do
    ENV["DEXPACE_SOURCES_TEST"] = "hello"
    begin
      seam = Dexpace::Configuration::Sources::ENVIRONMENT

      assert_equal("hello", seam.call("DEXPACE_SOURCES_TEST"))
      assert_nil(Dexpace::Configuration::Sources::ENVIRONMENT.call("dexpace_sources_test"))
      assert_nil(Dexpace::Configuration::Sources::ENVIRONMENT.call("DEXPACE_SOURCES_ABSENT"))
    ensure
      ENV.delete("DEXPACE_SOURCES_TEST")
    end
  end

  # CFG-2 is the chain's rule, not the seam's: the seam reports "" for a present-but-empty
  # variable exactly as ENV does, and Configuration#string is where "" falls through.
  test "CFG-11: ENVIRONMENT reports a present-but-empty variable as empty; CFG-2 is the chain's" do
    ENV["DEXPACE_SOURCES_EMPTY"] = ""
    begin
      assert_equal("", Dexpace::Configuration::Sources::ENVIRONMENT.call("DEXPACE_SOURCES_EMPTY"))
    ensure
      ENV.delete("DEXPACE_SOURCES_EMPTY")
    end
  end

  test "CFG-11: NONE answers nil for every key" do
    assert_nil(Dexpace::Configuration::Sources::NONE.call("ANY_KEY"))
    assert_nil(Dexpace::Configuration::Sources::NONE.call(""))
  end

  test "CFG-11: both shipped seams are frozen callables of arity one" do
    [Dexpace::Configuration::Sources::ENVIRONMENT,
     Dexpace::Configuration::Sources::NONE,].each do |seam|
      assert_predicate(seam, :frozen?)
      assert_respond_to(seam, :call)
      assert_equal(1, seam.arity)
    end
  end

  test "CFG-11: from_hash builds a hermetic frozen seam that owns a stringified copy of the map" do
    map = { "A" => "val-a", 123 => 456, :sym => "val-sym" }
    source = Dexpace::Configuration::Sources.from_hash(map)

    assert_predicate(source, :frozen?)
    assert_equal("val-a", source.call("A"))
    assert_equal("456", source.call("123"))
    assert_equal("val-sym", source.call("sym"))
    assert_nil(source.call("MISSING"))

    map["A"] = "mutated"
    map["NEW"] = "late"

    assert_equal("val-a", source.call("A"))
    assert_nil(source.call("NEW"))
  end

  test "CFG-11 / CFG-37: from_hash requires its map and refuses a nil value" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Configuration::Sources.from_hash(nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Configuration::Sources.from_hash([]) }
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Configuration::Sources.from_hash("a" => nil)
    end
  end

  test "P5-3: the environment seam is named ENVIRONMENT, and ::ENV is not shadowed" do
    refute(Dexpace::Configuration::Sources.const_defined?(:ENV, false))
    assert_same(::ENV, Dexpace::Configuration::Sources.module_eval("ENV", __FILE__, __LINE__))
  end
end
