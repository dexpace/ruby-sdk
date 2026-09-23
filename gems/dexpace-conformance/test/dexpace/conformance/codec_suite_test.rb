# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "json"
require "stringio"
require_relative "../../test_helper"
require "dexpace/conformance"

# Appendix B.3's seam half, proven against deliberately non-conforming codecs.
# SEAM-20, SERDE-3, SERDE-9.
class DexpaceConformanceCodecSuiteTest < DexpaceTestCase
  Suite = Dexpace::Conformance::CodecSuite

  # Built from phase 2's FILED contract: #dump_to(value, sink) and #load(source, witness). #dump
  # is deliberately NOT in CONTRACT, so no double defines it. The error hierarchy is phase 2's
  # too: SerializationError and DeserializationError descend from Dexpace::Serde::Error, and
  # there is no Dexpace::SerdeError.
  class ConformingCodec
    def dump_to(value, sink) = sink.write(value.inspect)

    def load(source, _witness)
      ::JSON.parse(source.read)
    rescue ::JSON::ParserError
      raise Dexpace::Serde::DeserializationError, "malformed JSON"
    end
  end

  # SEAM-20 / SERDE-3, broken: it closes the caller's sink.
  class ClosingCodec < ConformingCodec
    def dump_to(value, sink)
      super
      sink.close
    end
  end

  # SEAM-20 / SERDE-3, broken the other way: it closes nothing because it writes nothing.
  class SilentEncoder < ConformingCodec
    def dump_to(_value, _sink) = nil
  end

  # SERDE-9's "no library type escapes". A plain def, not `def … if cond`, which would define the
  # method conditionally and inherit the conforming parent's.
  class LeakyCodec < ConformingCodec
    def load(source, _witness) = ::JSON.parse(source.read)
  end

  # SERDE-9 requires the STABLE SERDE type: a Dexpace error outside that hierarchy is not it.
  class WrongFamilyCodec < ConformingCodec
    def load(_source, _witness) = raise(Dexpace::InvalidArgumentError, "not a serde error")
  end

  # SERDE-9's second clause: "chaining the original cause".
  class UnchainedCodec < ConformingCodec
    def load(_source, _witness)
      raise Dexpace::Serde::DeserializationError.new("malformed JSON"), cause: nil
    end
  end

  # SERDE-9's first clause: it does not raise at all.
  class SilentCodec < ConformingCodec
    def load(_source, _witness) = nil
  end

  # 7a's witness protocol is any object answering #dexpace_load(parsed, ctx); the source factory
  # stands in for the driver's, which for the JSON codec builds a Dexpace::IO::BufferedSource.
  WITNESS = Object.new
  def WITNESS.dexpace_load(parsed, _ctx) = parsed
  SOURCE = ->(text) { StringIO.new(text) }

  def run_suite(codec, **over)
    Suite.run(build: -> { codec.new }, witness: WITNESS, source: SOURCE, **over)
  end

  def statuses(report) = report.results.to_h { |r| [r.assertion.ids.first, r.status] }

  test "the suite covers exactly the three portable seam ids" do
    ids = Suite.assertions.flat_map(&:ids)

    assert_equal(%w[SEAM-20 SERDE-3 SERDE-9], ids.sort)
    refute_includes(ids, "SEAM-21", "the type-token rule stays in 7a's own suite")
    refute_includes(ids, "SERDE-10", "the mapping stays in 7a's own suite")
  end

  test "a conforming codec passes both seam assertions" do
    assert_equal({ "SEAM-20" => :passed, "SERDE-9" => :passed },
                 statuses(run_suite(ConformingCodec)),)
  end

  test "a codec that closes a caller-supplied sink fails SEAM-20 and SERDE-3 together" do
    report = run_suite(ClosingCodec)

    assert_equal(:failed, statuses(report)["SEAM-20"])
    assert_includes(report.to_s, "FAILED: SEAM-20, SERDE-3")
  end

  # Without this clause a codec that wrote nothing would pass by having closed nothing.
  test "a codec that writes nothing fails SEAM-20 rather than passing by omission" do
    assert_equal(:failed, statuses(run_suite(SilentEncoder))["SEAM-20"])
  end

  test "a library exception type escaping the seam fails SERDE-9" do
    assert_equal(:failed, statuses(run_suite(LeakyCodec))["SERDE-9"])
  end

  test "a Dexpace error outside the serde hierarchy fails SERDE-9" do
    assert_equal(:failed, statuses(run_suite(WrongFamilyCodec))["SERDE-9"])
  end

  test "a serde error with no chained cause fails SERDE-9" do
    assert_equal(:failed, statuses(run_suite(UnchainedCodec))["SERDE-9"])
  end

  test "a codec that does not raise at all fails SERDE-9" do
    assert_equal(:failed, statuses(run_suite(SilentCodec))["SERDE-9"])
  end

  # The rescue order inside the suite's own capture: Vacuous is a ::StandardError descendant, so
  # a bare rescue there would turn the suite's own vacuity into a pass.
  test "a Vacuous raised inside the body is not swallowed into passed" do
    vacuous = Class.new(ConformingCodec) do
      def load(_source, _witness)
        raise(Dexpace::Conformance::Vacuous, "this codec decodes nothing")
      end
    end

    assert_equal(:vacuous, statuses(run_suite(vacuous))["SERDE-9"])
  end

  test "a waiver by id suppresses exactly one result and leaves the other running" do
    report = run_suite(ClosingCodec, waive: ["SERDE-3"])

    assert_equal({ "SEAM-20" => :waived, "SERDE-9" => :passed }, statuses(report))
  end

  test "the preamble names what a green run does not prove" do
    report = run_suite(ConformingCodec)

    assert_includes(report.to_s, "SEAM-21")
    assert_includes(report.to_s, "SERDE-4")
    assert_operator(report.to_s, :start_with?, "dexpace-conformance codec suite:")
  end
end
