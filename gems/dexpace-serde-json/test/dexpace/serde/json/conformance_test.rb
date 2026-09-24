# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# SEAM-20, SERDE-3, SERDE-9. The first-party driver for dexpace-conformance's CodecSuite (phase 9's
# plan Task 10), placed in the adapter gem's own test tree exactly as 8a placed the transport
# suite's driver in dexpace-transport-net_http/test/.
#
# This gem's own seam_conformance_test.rb stays exactly as 7a wrote it and is NOT replaced by this
# file. The two are different claims: that one asserts six properties against THIS codec, four of
# which are not portable (SEAM-21's explicit type token, SERDE-4's buffer profile, SERDE-12's
# I/O-error pass-through, SERDE-29's shareability); this one asserts the two portable properties
# through the shared suite, which is what the post-v1 dexpace-serde-oj will be held to as well.
# Running both is the point -- a codec that passed the shared suite and failed the local one would
# be a codec the shared suite is too weak for, which is a finding about the suite.
require_relative "../../../test_helper"
require "dexpace/serde/json"
require "dexpace/conformance"

# The JSON codec's run of the shared codec suite: one generated test per assertion, plus the
# report-level check and one run under every option this adapter accepts.
class DexpaceSerdeJSONConformanceTest < DexpaceTestCase
  Conformance = Dexpace::Conformance
  SUITE = Conformance::CodecSuite

  # The one witness the two assertions need: the parsed value as it is. Named, not a lambda --
  # Serde.witness? is a respond_to? on .dexpace_load and NOTHING else makes a witness, so a
  # #call-shaped double would not be one (7a's R2).
  module PassThrough
    # @param parsed [Object] whatever the codec's parser produced
    # @return [Object] the same value
    def self.dexpace_load(parsed, _ctx) = parsed
  end

  # The source type THIS codec's #load reads. A different codec's driver passes a different one,
  # which is why the suite takes a factory rather than naming a class.
  SOURCE = ->(text) { Dexpace::IO::BufferedSource.of_bytes(text.b) }

  SUITE.assertions.each_with_index do |assertion, index|
    define_method(format("test_%<n>02d_%<name>s", n: index,
                                                  name: assertion.name.gsub(/\W+/, "_"),)) do
      drive(assertion)
    end
  end

  test "the suite reports no failure, no error and no MUST-level vacuity" do
    report = SUITE.run(**suite_arguments)

    assert_empty(report.failures.map { |result| described(result) })
    assert_empty(report.errors.map { |result| described(result) })
    assert_empty(report.blocking_vacuities.map { |result| result.assertion.ids.join(", ") })
    assert_empty(report.vacuous, "nothing here is vacuous: this gem supplies every factory")
    assert_predicate(report, :passed?)
  end

  # SERDE-3's "even when the codec's own auto-close feature is enabled" reaches every option this
  # adapter accepts, so the portable assertions are driven under each rather than under the
  # default alone -- the same widening 7a applied to its own suite.
  test "the portable seam properties hold under every accepted option" do
    [{ max_nesting: 4 }, { allow_nan: true }, { allow_duplicate_key: true }, { script_safe: true },
     { encoders: {} },].each do |options|
      report = SUITE.run(**suite_arguments(-> { Dexpace::Serde::JSON.build(options) }))

      assert_predicate(report, :passed?, "#{options.inspect}: #{report}")
    end
  end

  private

  def described(result) = "#{result.assertion.ids.join(", ")}: #{result.detail}"

  def drive(assertion)
    assertion.call(Conformance::CodecCase.new(**suite_arguments))
  rescue Conformance::Vacuous => error
    skip("vacuous: #{error.reason}")
  rescue Conformance::Failure => error
    flunk("#{assertion.ids.join(", ")}: #{error.message} (expected #{error.expected.inspect}, " \
          "got #{error.actual.inspect})")
  end

  # `.default` is a FRESH instance per call (7a's P7-4), so every assertion gets a codec of its own
  # without the driver arranging it.
  def suite_arguments(build = -> { Dexpace::Serde::JSON.default })
    { build: build, witness: PassThrough, source: SOURCE }
  end
end
