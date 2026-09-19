# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require "stringio"
require_relative "../../support/fake_body"

# Exercises: RETRY-5, RETRY-6, RETRY-7, RETRY-8, RECOV-18, HTTP-9, BODY-1; REDIR-6
#
# The re-sendability gate's four-cell truth table -- body-less idempotent and non-idempotent,
# body-bearing replayable and non-replayable -- plus the two single-source assertions: the
# idempotent set is phase 1's and the replayability answer is the body's own. Phase 6b's
# ReplayableBodyTest, below, pins the module's SECOND predicate beside it: the body-only
# question REDIR-6 asks, which says nothing about the method.
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

  # REDIR-6: the body-only predicate phase 6b adds beside 6a's .eligible? -- a request is
  # re-issuable on a method-preserving redirect iff it carries no body or its body is replayable.
  # Method eligibility for a redirect is REDIR-3/REDIR-4's configured allowed-method set, decided
  # in Redirect::Step and never here, so a body-less non-idempotent POST answers true where
  # .eligible? answers false (RETRY-7). Calling .eligible? at REDIR-6's site would refuse a
  # body-less POST 307 under an allowed_methods: the specification permits.
  class DexpaceResilienceResendReplayableBodyTest < DexpaceTestCase
    Resend = Dexpace::Resilience::Resend

    def request(method, body: nil)
      Dexpace::Request.build(method: Dexpace::Method.of(method), url: "https://example.test/x",
                             headers: Dexpace::Headers::EMPTY, body: body,)
    end

    test "REDIR-6: a request with no body is replayable, whatever its method" do
      %w[GET HEAD OPTIONS PUT DELETE POST PATCH].each do |method|
        assert(Resend.replayable_body?(request(method)), "#{method} with no body")
      end
    end

    test "REDIR-6: a body-bearing request is replayable iff its body says so (BODY-1)" do
      assert(Resend.replayable_body?(request("POST", body: FakeBody.new("x", replayable: true))))
      refute(Resend.replayable_body?(request("POST", body: FakeBody.new("x", replayable: false))))
      refute(Resend.replayable_body?(request("PUT", body: FakeBody.new("x", replayable: false))))
    end

    test "REDIR-6 against RETRY-7: the two predicates part on exactly the body-less POST" do
      bare_post = request("POST")

      assert(Resend.replayable_body?(bare_post))
      refute(Resend.eligible?(bare_post))
    end

    test "REDIR-6: the shipped bodies answer for themselves -- bytes yes, an owned stream no" do
      assert(Resend.replayable_body?(request("POST", body: Dexpace::Body.bytes("payload".b))))
      refute(Resend.replayable_body?(request("POST",
                                             body: Dexpace::Body.stream(StringIO.new("payload"),
                                                                        close: true,),)))
    end

    test "REDIR-6: replayable_body? asks nothing about the method, by source" do
      source = File.read(File.expand_path("../../../lib/dexpace/resilience/resend.rb", __dir__))
      body = source[/def replayable_body\?.*?^\s*end$/m]

      refute_nil(body)
      refute_match(/idempotent|method/, body)
    end
  end
end
