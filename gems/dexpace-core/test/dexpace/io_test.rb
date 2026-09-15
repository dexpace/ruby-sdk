# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# IO-9, and P3-8's naming of the constant.
class DexpaceIOTest < DexpaceTestCase
  test "MAX_MATERIALIZED_BYTES is design §3.1's 64 MiB, chosen and not derived" do
    assert_equal(64 * 1024 * 1024, Dexpace::IO::MAX_MATERIALIZED_BYTES)
    assert_predicate(Dexpace::IO::MAX_MATERIALIZED_BYTES, :frozen?)
  end

  # R5 is 3b's and phase 5 owns the configuration source. Nothing in 3a reads the ceiling from a
  # keyword, so this asserts the absence that phase 2's deadline: precedent (P2-5) depends on:
  # adding an optional keyword later widens a signature, and NFR-4 is not prejudiced.
  test "no 3a operation takes a max_materialized_bytes keyword" do
    methods = [Dexpace::IO::Buffer.instance_method(:snapshot),
               Dexpace::IO::TypedReads.instance_method(:read_exactly),
               Dexpace::IO::TypedReads.instance_method(:read_string),]
    keywords = methods.flat_map { |method| method.parameters.map(&:last) }

    refute_includes(keywords, :max_materialized_bytes)
  end

  # Pins the module's whole constant list, so a later phase that adds a class to Dexpace::IO has
  # to say so here as well as in the surface manifest.
  test "Dexpace::IO is a module and holds the streaming classes" do
    assert_kind_of(::Module, Dexpace::IO)
    assert_equal(%i[Buffer BufferedSink BufferedSource MAX_MATERIALIZED_BYTES TeeSink TypedReads
                    TypedWrites].sort,
                 Dexpace::IO.constants.sort,)
  end

  # The hazard Dexpace::IO's own YARD block states, measured rather than described: inside
  # `module Dexpace` a bare IO is this module and not Ruby's, so a nominal type test on a real
  # ::IO is silently false. This is why core writes `::IO` and respond_to?, never is_a?(IO), and
  # why Dexpace/QualifiedCoreConstant refuses the bare name. String evals, because a block's
  # constants resolve in the block's own lexical scope (verified on 3.2.11, 3.4.10 and 4.0.6),
  # and only a string eval gives the receiver's. The eval returns a lambda and the test hands it
  # the pipe end it owns and closes, so the probe leaks no descriptor of its own: a lambda keeps
  # the constant scope it was created in, which is the receiver's under a string eval.
  test "a bare IO inside module Dexpace is Dexpace::IO, not ::IO" do
    reader, writer = ::IO.pipe
    inside = Dexpace.module_eval("IO", __FILE__, __LINE__)
    probe = Dexpace.module_eval("->(x) { x.is_a?(IO) }", __FILE__, __LINE__)

    assert_same(Dexpace::IO, inside)
    refute_same(::IO, inside)
    assert_same(::IO, Dexpace.module_eval("::IO", __FILE__, __LINE__))
    assert_kind_of(::IO, reader)
    refute(probe.call(reader))
  ensure
    reader&.close
    writer&.close
  end

  # The consumer half of the finding docs/first-release.md carries as a blocker: a consumer's own
  # `class C; include Dexpace` puts Dexpace ahead of Object in C.ancestors, so a bare IO in C
  # resolves to Dexpace::IO and `x.is_a?(IO)` is silently false for a real ::IO. Nothing
  # mechanical reaches a consumer's file; the as-built documentation states it, and this pins
  # that the hazard is real rather than described.
  test "a consumer class that includes Dexpace sees Dexpace::IO for a bare IO" do
    consumer = Class.new { include Dexpace }
    reader, writer = ::IO.pipe
    probe = consumer.class_eval("->(x) { x.is_a?(IO) }", __FILE__, __LINE__)

    assert_same(Dexpace::IO, consumer.class_eval("IO", __FILE__, __LINE__))
    assert_kind_of(::IO, reader)
    refute(probe.call(reader))
  ensure
    reader&.close
    writer&.close
  end
end
