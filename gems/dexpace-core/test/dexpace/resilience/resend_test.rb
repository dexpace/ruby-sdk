# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require "stringio"
require_relative "../../support/fake_body"

# Exercises: RETRY-5, RETRY-6, RETRY-7, RETRY-8, RECOV-18, HTTP-9, BODY-1
#
# The re-sendability gate's four-cell truth table -- body-less idempotent and non-idempotent,
# body-bearing replayable and non-replayable -- plus the two single-source assertions: the
# idempotent set is phase 1's and the replayability answer is the body's own.
class DexpaceResilienceResendTest < DexpaceTestCase
  Resend = Dexpace::Resilience::Resend

  def request(method, body: nil)
    Dexpace::Request.build(method: Dexpace::Method.of(method), url: "https://example.test/x",
                           headers: Dexpace::Headers::EMPTY, body: body,)
  end

  test "RETRY-5 / RETRY-6: a body-less request is eligible iff its method is idempotent" do
    %w[GET HEAD OPTIONS PUT DELETE].each do |method|
      assert(Resend.eligible?(request(method)), "#{method} is idempotent")
    end
    %w[POST PATCH CONNECT TRACE].each do |method|
      refute(Resend.eligible?(request(method)), "#{method} is not idempotent")
    end
  end

  test "RETRY-6 / HTTP-9: the idempotent set is phase 1's single source, never a second list" do
    assert_equal(%w[GET HEAD OPTIONS PUT DELETE], Dexpace::Method::IDEMPOTENT)
    source = File.read(File.expand_path("../../../lib/dexpace/resilience/resend.rb", __dir__))
    code = source.gsub(/^\s*#.*$/, "")

    refute_match(/\b(GET|HEAD|OPTIONS|DELETE)\b/, code, "no second method set")
    assert_match(/idempotent\?/, code)
  end

  test "RETRY-7 / RECOV-18: a bare non-idempotent POST is NOT eligible, payload or no payload" do
    refute(Resend.eligible?(request("POST")))
    refute(Resend.eligible?(request("POST", body: FakeBody.new("x", replayable: false))))
  end

  test "RETRY-5 / BODY-1: a body-bearing request is eligible iff its body is replayable" do
    assert(Resend.eligible?(request("POST", body: FakeBody.new("x", replayable: true))))
    refute(Resend.eligible?(request("POST", body: FakeBody.new("x", replayable: false))))
    assert(Resend.eligible?(request("PATCH", body: FakeBody.new("x", replayable: true))),
           "POST/PATCH are re-sendable only via the replayable-body path (RETRY-6)",)
  end

  test "RETRY-8 / RECOV-18: an idempotent method with a non-replayable body is NOT eligible" do
    refute(Resend.eligible?(request("PUT", body: FakeBody.new("x", replayable: false))))
    refute(Resend.eligible?(request("DELETE", body: FakeBody.new("x", replayable: false))))
    assert(Resend.eligible?(request("PUT", body: FakeBody.new("x", replayable: true))))
  end

  test "RETRY-5: the shipped bodies answer for themselves -- bytes yes, an owned stream no" do
    bytes = Dexpace::Body.bytes("payload".b)
    stream = Dexpace::Body.stream(StringIO.new("payload"), close: true)

    assert(Resend.eligible?(request("POST", body: bytes)))
    refute(Resend.eligible?(request("POST", body: stream)), "close: true forces single use")
  end
end
