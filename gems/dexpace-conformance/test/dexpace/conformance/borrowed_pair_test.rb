# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# Suite contract 4a (8a's R16): what a driver's `borrow:` factory returns -- the transport that
# wraps the caller's own client, and a probe answering "is that client still usable?" -- so
# TRANSPORT-15's borrowed half never names a native client class inside this gem.
class DexpaceConformanceBorrowedPairTest < DexpaceTestCase
  BorrowedPair = Dexpace::Conformance::BorrowedPair

  test "carries the transport and the probe; #still_usable? is the probe's answer as a boolean" do
    pair = BorrowedPair.build(transport: :t, probe: -> { "yes" })

    assert_equal(:t, pair.transport)
    assert_predicate(pair, :still_usable?)
    refute_predicate(BorrowedPair.build(transport: :t, probe: -> {}), :still_usable?)
    assert_predicate(pair, :frozen?)
  end

  test "HTTP-4 / SEAM-29: both members are required, in the one message form; a callable probe" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      BorrowedPair.build(transport: nil, probe: -> {})
    end

    assert_equal("transport is required", error.message)
    assert_equal("probe is required",
                 assert_raises(Dexpace::InvalidArgumentError) do
                   BorrowedPair.build(transport: :t, probe: nil)
                 end.message,)
    assert_raises(Dexpace::InvalidArgumentError) do
      BorrowedPair.build(transport: :t, probe: :not_callable)
    end
  end

  test "HTTP-2: the constructor is private, so .build is the one entry point" do
    assert_raises(NoMethodError) { BorrowedPair.new(transport: :t, probe: -> {}) }
  end
end
