# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recovery_fixtures"
require "dexpace"

# RECOV-33. HTTP-5's second tier: Headers#[] returns the name's own frozen VALUE LIST, which is
# what makes "preserving all other pre-existing values" assertable at all. The requirement's two
# easy-to-miss halves -- the blank-line no-op and the empty-first-value rule -- each get a test.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# reconciliation rules here, the no-op and construction rules below.
class DexpaceRecoveryClientIdentityStepTest < DexpaceTestCase
  # Shared by both classes below.
  module Steps
    include RecoveryFixtures

    UA = "User-Agent"

    def build_step(tokens:, **)
      Dexpace::Recovery::ClientIdentityStep.build(header: UA, tokens: tokens, **)
    end
  end
  include Steps

  test "is a :request transform exposing its frozen configuration" do
    step = build_step(tokens: ["dexpace/1.0"])

    assert_kind_of(Dexpace::Recovery::Transform, step)
    assert_equal(:request, step.phase)
    assert_equal(UA, step.header)
    assert_equal(["dexpace/1.0"], step.tokens)
    assert_predicate(step.tokens, :frozen?)
    assert_equal(:append, step.mode)
  end

  test "sets the joined token line as the sole value when the header is absent" do
    step = build_step(tokens: ["sdk/1.0", "custom/2.0"])
    request = build_request

    result = step.apply(request)

    refute_same(request, result)
    assert_equal(["sdk/1.0 custom/2.0"], result.headers[UA])
  end

  test "append puts the line after the first existing value, space-separated" do
    step = build_step(tokens: ["sdk/1.0"])
    request = build_request(headers: headers_with(UA, "host-client/3.0"))

    assert_equal(["host-client/3.0 sdk/1.0"], step.apply(request).headers[UA])
  end

  # RECOV-33's parenthesis, and the half a single-valued fixture cannot catch: append touches the
  # FIRST value and preserves every other pre-existing one, so Headers::Builder#set alone --
  # which replaces the whole list -- is the wrong mechanism.
  test "append preserves every pre-existing value after the first, in order" do
    step = build_step(tokens: ["sdk/1.0"])
    request = build_request(headers: headers_with(UA, "host-client/3.0", "proxy/1.2", "edge/0.9"))

    assert_equal(["host-client/3.0 sdk/1.0", "proxy/1.2", "edge/0.9"],
                 step.apply(request).headers[UA],)
  end

  # In append mode an empty first existing value is treated as absent, so no leading space.
  test "append treats an empty first existing value as absent and emits no leading space" do
    step = build_step(tokens: ["sdk/1.0"])

    assert_equal(["sdk/1.0"], step.apply(build_request(headers: headers_with(UA, ""))).headers[UA])
    assert_equal(["sdk/1.0", "proxy/1.2"],
                 step.apply(build_request(headers: headers_with(UA, "", "proxy/1.2"))).headers[UA],)
  end

  test "replace overwrites every existing value with the line" do
    step = build_step(tokens: ["sdk/2.0"], mode: :replace)
    request = build_request(headers: headers_with(UA, "old-client/1.0", "proxy/1.2"))

    assert_equal(["sdk/2.0"], step.apply(request).headers[UA])
    assert_equal(["sdk/2.0"], step.apply(build_request).headers[UA])
  end

  test "other headers on the request are carried through untouched" do
    step = build_step(tokens: ["sdk/1.0"])
    request = build_request(headers: headers_with("Accept", "application/json"))

    result = step.apply(request)

    assert_equal(["application/json"], result.headers["Accept"])
    assert_equal(["sdk/1.0"], result.headers[UA])
  end

  # The no-op clause, and construction.
  class NoOpTest < DexpaceTestCase
    include Steps

    # RECOV-33's last clause: no blank or whitespace-only header, ever, and the request comes
    # back by identity.
    test "an empty token list is a no-op returning the request by identity" do
      request = build_request

      assert_same(request, build_step(tokens: []).apply(request))
    end

    test "tokens joining to a blank or whitespace-only line are a no-op in both modes" do
      request = build_request(headers: headers_with(UA, "existing/1.0"))

      assert_same(request, build_step(tokens: ["  ", ""]).apply(request))
      assert_same(request, build_step(tokens: ["", "\t"], mode: :replace).apply(request))
      assert_equal(["existing/1.0"], request.headers[UA])
    end

    test "the token line is trimmed and inner whitespace-only tokens are dropped" do
      step = build_step(tokens: [" sdk/1.0 ", "", "custom/2.0"])

      assert_equal(["sdk/1.0 custom/2.0"], step.apply(build_request).headers[UA])
    end

    # RECOV-14: the caller's token array is copied at construction.
    test "the token list is copied and frozen at construction" do
      tokens = ["sdk/1.0"]
      step = build_step(tokens: tokens)

      tokens << "late/9.9"

      assert_equal(["sdk/1.0"], step.tokens)
      assert_equal(["sdk/1.0"], step.apply(build_request).headers[UA])
    end

    test "build validates the header name, the token list and the mode" do
      build = Dexpace::Recovery::ClientIdentityStep.method(:build)

      assert_raises(Dexpace::InvalidArgumentError) { build.call(header: nil, tokens: ["t"]) }
      assert_raises(Dexpace::InvalidArgumentError) { build.call(header: "Bad Name", tokens: ["t"]) }
      assert_raises(Dexpace::InvalidArgumentError) { build_step(tokens: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { build_step(tokens: "sdk/1.0") }
      assert_raises(Dexpace::InvalidArgumentError) { build_step(tokens: [:sym]) }
      assert_raises(Dexpace::InvalidArgumentError) { build_step(tokens: ["t"], mode: :unknown) }
      assert_raises(::NoMethodError) do
        Dexpace::Recovery::ClientIdentityStep.new(header: UA, tokens: ["t"], mode: :append)
      end
    end

    # A token that cannot be carried on the wire is refused by phase 1's own value validation.
    test "a token line that is not a valid header value is refused at apply" do
      step = build_step(tokens: ["bad\r\ntoken"])

      assert_raises(Dexpace::InvalidArgumentError) { step.apply(build_request) }
    end
  end
end
