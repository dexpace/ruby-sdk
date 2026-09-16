# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recovery_fixtures"
require "dexpace"

# RECOV-32. HTTP-5's second tier: Headers#[] returns the name's own frozen VALUE LIST, so every
# header assertion here compares an Array. The strategy is counted rather than inspected, because
# "burns a key per redirect hop" is invisible to a test that only checks the header.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# stamping rules here, the construction rules below.
class DexpaceRecoveryIdempotencyKeyStepTest < DexpaceTestCase
  # Shared by both classes below.
  module Steps
    include RecoveryFixtures

    KEY = "Idempotency-Key"

    def counting_strategy(key)
      calls = 0
      strategy = lambda do |_request|
        calls += 1
        key
      end
      [strategy, -> { calls }]
    end

    def build_step(strategy:, **)
      Dexpace::Recovery::IdempotencyKeyStep.build(header: KEY, strategy: strategy, **)
    end
  end
  include Steps

  test "is a :request transform exposing its frozen configuration" do
    strategy = ->(_) { "k1" }

    step = build_step(strategy: strategy)

    assert_kind_of(Dexpace::Recovery::Transform, step)
    assert_equal(:request, step.phase)
    assert_equal(KEY, step.header)
    assert_same(strategy, step.strategy)
    assert_equal([Dexpace::Method::POST, Dexpace::Method::PUT, Dexpace::Method::PATCH],
                 step.methods,)
    assert_predicate(step.methods, :frozen?)
    assert_equal(:respect_existing, step.mode)
  end

  test "a method outside the set passes through by identity and the strategy is not called" do
    strategy, calls = counting_strategy("k1")
    step = build_step(strategy: strategy)

    %i[GET HEAD DELETE OPTIONS].each do |name|
      request = build_request(method: Dexpace::Method.const_get(name))

      assert_same(request, step.apply(request))
    end
    assert_equal(0, calls.call)
  end

  test "an applicable method is stamped once, and the strategy is invoked exactly once" do
    strategy, calls = counting_strategy("unique-key")
    step = build_step(strategy: strategy)
    request = build_request(method: Dexpace::Method::POST)

    result = step.apply(request)

    refute_same(request, result)
    assert_equal(["unique-key"], result.headers[KEY])
    assert_equal(1, calls.call)
    assert_equal(request.url, result.url)
    assert_same(request.method, result.method)
  end

  test "the strategy receives the request it is minting a key for" do
    seen = nil
    step = build_step(strategy: lambda { |request|
      seen = request
      "k"
    })
    request = build_request(method: Dexpace::Method::PUT)

    step.apply(request)

    assert_same(request, seen)
  end

  # §5.1's own emphasis: a request already carrying the header is returned by identity AND the
  # strategy is not called at all, or a redirect hop burns a key.
  test "respect_existing leaves a request already carrying the header alone, strategy uncalled" do
    strategy, calls = counting_strategy("fresh-key")
    step = build_step(strategy: strategy)
    request = build_request(method: Dexpace::Method::POST,
                            headers: headers_with("idempotency-key", "existing-key"),)

    result = step.apply(request)

    assert_same(request, result)
    assert_equal(["existing-key"], result.headers[KEY])
    assert_equal(0, calls.call)
  end

  test "overwrite replaces every existing value with the strategy's, invoked once" do
    strategy, calls = counting_strategy("new-key")
    step = build_step(strategy: strategy, mode: :overwrite)
    request = build_request(method: Dexpace::Method::PATCH,
                            headers: headers_with(KEY, "old-1", "old-2"),)

    result = step.apply(request)

    refute_same(request, result)
    assert_equal(["new-key"], result.headers[KEY])
    assert_equal(1, calls.call)
  end

  # Construction: the method set and the four validated arguments.
  class ConstructionTest < DexpaceTestCase
    include Steps

    test "a configured method set replaces the default entirely" do
      strategy, calls = counting_strategy("k")
      step = build_step(strategy: strategy, methods: [Dexpace::Method::DELETE])
      post = build_request(method: Dexpace::Method::POST)
      delete = build_request(method: Dexpace::Method::DELETE)

      assert_same(post, step.apply(post))
      assert_equal(["k"], step.apply(delete).headers[KEY])
      assert_equal(1, calls.call)
    end

    # RECOV-14: the caller's array is copied at construction.
    test "the method set is copied and frozen at construction" do
      methods = [Dexpace::Method::POST]
      step = build_step(strategy: ->(_) { "k" }, methods: methods)

      methods << Dexpace::Method::GET
      get = build_request(method: Dexpace::Method::GET)

      assert_equal([Dexpace::Method::POST], step.methods)
      assert_same(get, step.apply(get))
      assert_raises(::FrozenError) { step.methods << Dexpace::Method::GET }
    end

    test "build validates the header name, the strategy, the method set and the mode" do
      strategy = ->(_) { "k" }
      build = Dexpace::Recovery::IdempotencyKeyStep.method(:build)

      assert_raises(Dexpace::InvalidArgumentError) { build.call(header: nil, strategy: strategy) }
      assert_raises(Dexpace::InvalidArgumentError) do
        build.call(header: "Bad Name", strategy: strategy)
      end
      assert_raises(Dexpace::InvalidArgumentError) { build_step(strategy: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { build_step(strategy: :not_callable) }
      assert_raises(Dexpace::InvalidArgumentError) do
        build_step(strategy: strategy, methods: ["POST"])
      end
      assert_raises(Dexpace::InvalidArgumentError) { build_step(strategy: strategy, mode: :bad) }
      assert_raises(::NoMethodError) do
        Dexpace::Recovery::IdempotencyKeyStep.new(header: KEY, strategy: strategy)
      end
    end

    # A strategy that returns something a header cannot carry is the caller's mistake, and it is
    # reported by phase 1's own value validation rather than smuggled onto the wire.
    test "a strategy result that is not a valid header value is refused" do
      step = build_step(strategy: ->(_) { "a\r\nb" })

      assert_raises(Dexpace::InvalidArgumentError) do
        step.apply(build_request(method: Dexpace::Method::POST))
      end
    end
  end
end
