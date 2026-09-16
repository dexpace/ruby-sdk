# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recovery_fixtures"
require "dexpace"

# RECOV-3, RECOV-14. Every step here is a bare lambda, which is both the cheapest fixture and the
# assertion that §5.1's "a lambda qualifies as a step" is true of the recovery chain (R8 clause
# 3); the shipped transforms get their own suites and are not used as fixtures for the fold.
class DexpaceRecoveryRequestChainTest < DexpaceTestCase
  include RecoveryFixtures

  test "an empty chain returns the input request unchanged, by identity" do
    chain = Dexpace::Recovery::RequestChain.build
    request = build_request

    assert_same(request, chain.apply(request))
    assert_equal([], chain.steps)
    assert_predicate(chain.steps, :frozen?)
  end

  # Request#url is the frozen URI::Generic that URL.parse! returned, so the assertion goes
  # through #to_s -- comparing a String to a URI silently fails.
  test "applies the steps as a left-to-right fold: step N's output is step N+1's input" do
    first = ->(request) { request.with(url: "#{request.url}/first") }
    second = ->(request) { request.with(url: "#{request.url}/second") }
    chain = Dexpace::Recovery::RequestChain.build(steps: [first, second])

    assert_equal("https://example.test/api/first/second", chain.apply(build_request).url.to_s)
  end

  test "a transform installs as a step by its own #call, with no adapter (R8 clause 4)" do
    identity = Dexpace::Recovery::ClientIdentityStep.build(header: "User-Agent", tokens: ["sdk/1"])
    chain = Dexpace::Recovery::RequestChain.build(steps: [identity])

    assert_equal(["sdk/1"], chain.apply(build_request).headers["User-Agent"])
  end

  # RECOV-3's own text: this chain is NOT total. Both halves are asserted -- the raise reaches
  # the caller AND the steps after the thrower were not invoked.
  test "a throwing step aborts the remaining steps and propagates to the caller" do
    ran = []
    steps = [
      lambda { |request|
        ran << :first
        request
      },
      lambda { |_request|
        ran << :second
        raise ::IOError, "step 2 broke"
      },
      lambda { |request|
        ran << :third
        request
      },
    ]
    chain = Dexpace::Recovery::RequestChain.build(steps: steps)

    error = assert_raises(::IOError) { chain.apply(build_request) }

    assert_equal("step 2 broke", error.message)
    assert_equal(%i[first second], ran)
  end

  # RECOV-14, resolved toward the stricter behaviour (P4-22): the caller's array is copied and
  # frozen at construction, and #steps returns that frozen copy itself (HTTP-5's second tier).
  test "copies and freezes the step list at construction, and #steps is that copy" do
    caller_steps = [->(request) { request }]
    chain = Dexpace::Recovery::RequestChain.build(steps: caller_steps)

    caller_steps << ->(request) { request.with(url: "https://mutated.test/") }

    assert_equal(1, chain.steps.size)
    assert_predicate(chain.steps, :frozen?)
    assert_same(chain.steps, chain.steps)
    assert_raises(::FrozenError) { chain.steps << ->(request) { request } }
    assert_equal("https://example.test/api", chain.apply(build_request).url.to_s)
  end

  test "a step that returns something that is not a Request is refused before the next step" do
    ran = false
    steps = [
      ->(_request) { "not a request" },
      lambda { |request|
        ran = true
        request
      },
    ]
    chain = Dexpace::Recovery::RequestChain.build(steps: steps)

    assert_raises(Dexpace::InvalidArgumentError) { chain.apply(build_request) }
    refute(ran, "the step after a non-Request return must not run")
  end

  test "build validates the step list and apply validates its argument" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::RequestChain.build(steps: nil)
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::RequestChain.build(steps: [:not_callable])
    end
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Recovery::RequestChain.build.apply(:not_a_request)
    end
    assert_raises(::NoMethodError) { Dexpace::Recovery::RequestChain.new(steps: []) }
  end
end
