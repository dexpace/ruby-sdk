# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/assertion_probe"
require_relative "../../../support/raw_wire_transport"
require_relative "../../../support/stub_transport"
require_relative "../../../support/non_conforming_transport"
require "dexpace/conformance"

# Group 5 (8a plan Task 13): TRANSPORT-5, 6, 15, 16, 29 and phase 7c's PAGE-36, each proven in
# both directions. This is also the file that pins the registry's size: the whole suite was 28
# assertions in five groups, one of them vacuous by measurement, until phase 8c appended its two
# (asynchronous_test.rb, header_drops_test.rb) -- 34 in seven, TRANSPORT-8 still absent by
# decision.
class DexpaceConformanceLifecycleAssertionsTest < DexpaceTestCase
  include AssertionProbe

  def borrow_with(probe_answer)
    lambda do |_port|
      Dexpace::Conformance::BorrowedPair.build(transport: RawWireTransport.new(owned: false),
                                               probe: -> { probe_answer },)
    end
  end

  # Twenty-eight in five groups until phase 8c added its six assertions in two groups after this
  # one (TRANSPORT-7, 9, 21, 23, then 12 and 13 -- and not TRANSPORT-8, which PREAMBLE names as
  # the third thing a green run does not prove): 34 in seven.
  test "the suite is exactly 34 assertions in seven groups, this one fifth" do
    assert_equal(34, Suite.assertions.size)
    assert_equal([%w[TRANSPORT-5], %w[TRANSPORT-6], %w[TRANSPORT-15], %w[TRANSPORT-15 TRANSPORT-16],
                  %w[TRANSPORT-29], %w[PAGE-36],], Suite.assertions[22, 6].map(&:ids),)
    ids = Suite.assertions.flat_map(&:ids).uniq

    assert_equal(28, ids.grep(/\ATRANSPORT-/).size,
                 "8a's 23 own IDs minus TRANSPORT-30, whose proxy assertions are the adapter's " \
                 "own, plus 8c's six portable ones",)
    refute_includes(ids, "TRANSPORT-8")
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
