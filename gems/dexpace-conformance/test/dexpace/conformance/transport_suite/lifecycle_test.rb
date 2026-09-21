# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/assertion_probe"
require_relative "../../../support/raw_wire_transport"
require_relative "../../../support/stub_transport"
require_relative "../../../support/non_conforming_transport"
require "dexpace/conformance"

# Group 5 (8a plan Task 13): TRANSPORT-5, 6, 15, 16, 29 and phase 7c's PAGE-36, each proven in
# both directions. This is also the file that closes the registry: the whole suite is 28
# assertions, one of them vacuous by measurement, none of them TRANSPORT-12's or TRANSPORT-13's
# (phase 8c's rows, asserted by 8c's driver).
class DexpaceConformanceLifecycleAssertionsTest < DexpaceTestCase
  include AssertionProbe

  def borrow_with(probe_answer)
    lambda do |_port|
      Dexpace::Conformance::BorrowedPair.build(transport: RawWireTransport.new(owned: false),
                                               probe: -> { probe_answer },)
    end
  end

  test "the suite is exactly 28 assertions in five groups, with no TRANSPORT-12 or TRANSPORT-13" do
    assert_equal(28, Suite.assertions.size)
    assert_equal([%w[TRANSPORT-5], %w[TRANSPORT-6], %w[TRANSPORT-15], %w[TRANSPORT-15 TRANSPORT-16],
                  %w[TRANSPORT-29], %w[PAGE-36],], Suite.assertions[22, 6].map(&:ids),)
    ids = Suite.assertions.flat_map(&:ids).uniq

    assert_empty(ids & %w[TRANSPORT-12 TRANSPORT-13])
    assert_equal(22, ids.grep(/\ATRANSPORT-/).size,
                 "the 23 own IDs minus TRANSPORT-30, whose proxy assertions are the adapter's own",)
  end

  test "TRANSPORT-5: two concurrent calls each bounded by its own timeout pass; sticky fails" do
    assertion = find("TRANSPORT-5")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:sticky_timeout), matching: /did not bound their own calls/)
  end

  test "TRANSPORT-6: a near-zero timeout that still bounds the call passes; non-retryable fails" do
    assertion = find("TRANSPORT-6")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:non_retryable_timeout), matching: /did not bound the call/)
  end

  test "TRANSPORT-15 (borrowed): a usable client passes; a broken one fails; no factory: vacuous" do
    assertion = find_all("TRANSPORT-15")[0]

    assert_passes(assertion, build: raw, borrow: borrow_with(true))
    assert_fails(assertion, build: raw, borrow: borrow_with(false), matching: /did not survive/)
    assert_vacuous(assertion, build: raw, matching: /TRANSPORT-15/)
  end

  test "TRANSPORT-15/16 (owned): ClosedError after two closes passes; a send after close fails" do
    assertion = find("TRANSPORT-16")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:send_after_close), matching: /did not raise ClosedError/)
    assert_fails(assertion, build: lambda { |**_|
      NonConformingTransport.new
    }, matching: /did not raise ClosedError/,)
  end

  test "TRANSPORT-29: 160 concurrent echoes each matched to its request pass; a cached one fails" do
    assertion = find("TRANSPORT-29")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:cached_response), matching: /wrong request/)
  end

  test "PAGE-36: two pages under two different options pass; reusing the first response fails" do
    assertion = find("PAGE-36")

    assert_passes(assertion, build: raw)
    assert_fails(assertion, build: raw(:cached_response), matching: /did not reach a fresh page/)
  end
end
