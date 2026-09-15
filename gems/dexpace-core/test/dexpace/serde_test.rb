# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/fake_codec"
require_relative "../support/incomplete_codec"
require "dexpace"
require "stringio"

# SEAM-19, SEAM-20, SEAM-21, SEAM-22's surviving clause, SEAM-2. The seam is a duck type of six
# methods: all four of SEAM-20's allocation profiles ship, and two of them are one Ruby type -- a
# String tagged Encoding::BINARY *is* Ruby's byte array, so #dump_bytes differs from #dump_string
# only in the encoding tag, which is the whole of the distinction the requirement draws (§10.13).
class DexpaceSerdeTest < DexpaceTestCase
  CORE = "~> 0.0"

  test "conforms? requires all six seam methods and names the missing ones" do
    assert(Dexpace::Serde.conforms?(FakeCodec.new))
    refute(Dexpace::Serde.conforms?(IncompleteCodec.new))
    refute(Dexpace::Serde.conforms?(Object.new))

    assert_equal(%i[dump_into], Dexpace::Serde.missing_methods(IncompleteCodec.new))
    assert_empty(Dexpace::Serde.missing_methods(FakeCodec.new))
  end

  test "the media type is never defaulted at the seam level" do
    refute_respond_to(Dexpace::Serde, :media_type,
                      "SEAM-19: the seam supplies no default and has no fallback to fall back to",)
    assert_equal("application/vnd.dexpace.fake", FakeCodec.new.media_type)
  end

  test "a codec that forgets media_type fails conformance rather than stamping the wrong type" do
    forgetful = Class.new(FakeCodec) do
      undef_method :media_type
    end.new

    refute(Dexpace::Serde.conforms?(forgetful))
    assert_equal(%i[media_type], Dexpace::Serde.missing_methods(forgetful))
  end

  test "the registry starts empty and its error names this seam and no gem" do
    assert_empty(Dexpace::Serde.registered_keys)

    error = assert_raises(Dexpace::SeamError) { Dexpace::Serde.resolve }

    assert_match(/no codec provider is registered/, error.message)
    assert_match(/Dexpace::Serde\.install/, error.message)
    refute_match(/json|oj/i, error.message, "SEAM-2")
  end

  test "install refuses a codec that does not implement the seam" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Serde.install(IncompleteCodec.new)
    end

    assert_match(/must implement the seam/, error.message)
  end

  test "swap scopes a codec override to its block" do
    codec = FakeCodec.new

    Dexpace::Serde.swap(codec) do
      assert_same(codec, Dexpace::Serde.resolve)
    end

    assert_raises(Dexpace::SeamError) { Dexpace::Serde.resolve }
  end

  test "install goes through the module, returns it, and is scoped by an enclosing swap" do
    codec = FakeCodec.new

    Dexpace::Serde.swap(:override) do
      assert_same(Dexpace::Serde, Dexpace::Serde.install(codec))
      assert_same(codec, Dexpace::Serde.resolve)
    end

    assert_raises(Dexpace::SeamError) { Dexpace::Serde.resolve }
  end

  # Scoped inside a swap and cleaned out of the private registry afterwards, for the reason
  # transport_test.rb gives: registrations are process-global and kept by design.
  test "register goes through the module and returns the module" do
    Dexpace::Serde.swap(FakeCodec.new) do
      assert_same(Dexpace::Serde, Dexpace::Serde.register(:probe, FakeCodec, core: CORE))
      assert_includes(Dexpace::Serde.registered_keys, :probe)
    end
  ensure
    registry = Dexpace::Serde.const_get(:REGISTRY, false)
    state = registry.instance_variable_get(:@state)
    registry.instance_variable_set(:@state, state.with(factories: state.factories.except(:probe)))
  end

  # SEAM-20 and SEAM-21's never-close rule, asserted against the fake so the seam's own harness is
  # not the first place it is tried; dexpace-conformance asserts it per adapter.
  test "the streaming and buffer variants never close the caller's target" do
    codec = FakeCodec.new
    sink = StringIO.new(+"")

    codec.dump_to(:payload, sink)

    refute_predicate(sink, :closed?, "SEAM-20: a streaming variant must not close the sink")

    source = StringIO.new("payload")
    codec.load(source, ->(text) { text })

    refute_predicate(source, :closed?, "SEAM-21: decode reads to EOF and does not close the source")
  end

  test "dump_bytes and dump_string differ exactly in the encoding tag" do
    codec = FakeCodec.new

    assert_equal(Encoding::BINARY, codec.dump_bytes(:payload).encoding)
    assert_equal("payload", codec.dump_bytes(:payload).force_encoding(Encoding::UTF_8))
    assert_equal("payload", codec.dump_string(:payload))
  end

  test "dump_into writes at the offset and raises IndexError on overflow" do
    buffer = +"          "

    assert_equal(7, FakeCodec.new.dump_into(:payload, buffer, offset: 2))
    assert_equal("  payload ", buffer)
    assert_raises(::IndexError) do
      FakeCodec.new.dump_into(:a_long_payload, +"    ", offset: 0)
    end
  end

  # SEAM-22's mechanism -- a reflective generic type capture -- is replaced by the witness protocol
  # (§10.14, §7.3, phase 7). The clause that survives the substitution is fixed here: #load takes an
  # explicit witness and there is no witness-less overload.
  test "load requires an explicit witness" do
    assert_raises(::ArgumentError) { FakeCodec.new.load(StringIO.new("x")) }
  end

  test "the seam module has no instance side to include by accident" do
    assert_empty(Dexpace::Serde.instance_methods(false))
  end
end
