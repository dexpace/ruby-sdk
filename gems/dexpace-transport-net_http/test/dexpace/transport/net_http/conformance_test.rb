# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require_relative "../../../support/net_http_hermetic_proxy"
require "dexpace/transport/net_http"
require "dexpace/conformance"

# The shared conformance suite run against the real adapter (8a's R16, the suite contract):
# one generated test per assertion, driven through MinitestDriver with no `settle:`, `around:`
# or `wire:` -- the defaults ARE this adapter's shape -- and `waive: []`, because TRANSPORT-28's
# zero-copy clause has no assertion to suppress. Three report vacuous BY MEASUREMENT (a skip in
# Minitest's vocabulary): TRANSPORT-18, because with max_retries = 0 no native re-subscription
# exists; and, since phase 8c appended its six portable assertions, TRANSPORT-12 and TRANSPORT-13,
# because net-http sends a model-valid non-token name rather than rejecting it -- the same
# antecedent this file's own cross-reference test measures absent. 8c's other four (TRANSPORT-7,
# 9, 21, 23) pass against this adapter as real properties of it.
# The class inherits DexpaceTestCase so a fixture thread an assertion leaked fails the test that
# leaked it, and includes NetHTTPHermeticProxy so the adapter every assertion builds resolves no
# proxy from the host's environment.
class DexpaceTransportNetHttpConformanceTest < DexpaceTestCase
  include NetHTTPHermeticProxy
  extend Dexpace::Conformance::MinitestDriver

  NetHTTP = Dexpace::Transport::NetHTTP

  conformance(
    Dexpace::Conformance::TransportSuite,
    build: ->(**settings) { NetHTTP.build(**settings) },
    # Suite contract 4a: the factory takes the fixture's PORT and returns a BorrowedPair, so no
    # assertion inside dexpace-conformance ever names ::Net::HTTP. The client is bound to that
    # port because a borrowing transport refuses any other origin (P8-15), and max_retries is set
    # by the CALLER, never by `.using`, which refuses a client that lacks it (P8-10). The probe is
    # a real round trip through the client itself: the only thing that proves the transport's
    # close did not touch it. The explicit nil proxy keeps the client off Net::HTTP's `:ENV`
    # default, whose HTTP_PROXY warning the test base makes fatal (R2-1).
    borrow: lambda do |port|
      client = ::Net::HTTP.new("127.0.0.1", port, nil, nil, nil, nil)
      client.max_retries = 0
      Dexpace::Conformance::BorrowedPair.build(
        transport: NetHTTP.using(client),
        probe: lambda do
          client.start { |c| c.request(::Net::HTTP::Get.new("/")) }.code == "200"
        rescue ::StandardError
          false
        end,
      )
    end,
    waive: [],
  )

  # The driver's own contract, checked rather than assumed: every assertion in the suite became
  # a test method here. The suite carries TRANSPORT-12 and TRANSPORT-13 since phase 8c, whose
  # rows they are; against this adapter each resolves vacuous by measurement (the skips above).
  test "one generated test per assertion, 8c's six included" do
    generated = public_methods(false).grep(/\Atest_/).reject do |name|
      name.to_s.start_with?("test_: ")
    end
    ids = Dexpace::Conformance::TransportSuite.assertions.flat_map(&:ids).uniq

    assert_equal(Dexpace::Conformance::TransportSuite.assertions.size, generated.size)
    assert_equal(34, generated.size)
    assert_includes(ids, "TRANSPORT-12")
    assert_includes(ids, "TRANSPORT-13")
  end

  # What a real third-party adapter author would write: the borrow lambda sets max_retries = 0
  # first, and writing it wrong fails loudly rather than silently.
  test "TRANSPORT-15's borrowed half genuinely refuses a client with a non-zero max_retries" do
    assert_raises(Dexpace::InvalidArgumentError) { NetHTTP.using(::Net::HTTP.new("127.0.0.1", 1)) }
  end

  # TRANSPORT-12 and TRANSPORT-13 are 8c's rows; here they are cross-references whose antecedent
  # is MEASURED absent: a header valid at the SDK model layer is never rejected by net-http's own
  # wire grammar, so there is no per-header drop to make and no drop-logging policy to expose.
  # The measurement walks every byte the outbound value grammar admits and every token byte a
  # name admits, through the same native call the mapper makes.
  test "TRANSPORT-12/13 cross-reference: net-http rejects no model-valid header (no antecedent)" do
    admitted_values = (0x20..0x7E).map(&:chr) << "\t"
    admitted_values.select! { |byte| Dexpace::HeaderSyntax.valid_outbound_value?("a#{byte}b") }
    admitted_names = (0x21..0x7E).map(&:chr).select { |byte| Dexpace::HeaderSyntax.valid_name?("x#{byte}") }
    native = ::Net::HTTPGenericRequest.new("GET", false, true, "/", {})

    admitted_values.each { |byte| native.add_field("X-Value", "a#{byte}b") }
    admitted_names.each { |byte| native.add_field("x#{byte}", "v") }

    refute_empty(admitted_values)
    refute_empty(admitted_names)
    assert_equal(admitted_values.size, native.get_fields("X-Value").size)
  end
end
