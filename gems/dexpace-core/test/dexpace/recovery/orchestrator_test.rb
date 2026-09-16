# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recovery_fixtures"
require_relative "../../support/fake_transport"
require "dexpace"

# RECOV-2, RECOV-10, RECOV-11, RETRY-25. The transport is phase 2's FakeTransport -- the
# #call(request, options, cancellation) duck type, recording every triple -- and the orchestrator
# is itself one of those by the same duck type, which is what lets a recovery-aware stack nest.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the send
# path and RECOV-2 here, the unwrap (RECOV-10, RECOV-11) and the fatal family below.
class DexpaceRecoveryOrchestratorTest < DexpaceTestCase
  # Shared by every class below.
  module Orchestrators
    include RecoveryFixtures

    def orchestrate(transport, request_chain: nil, response_chain: nil, **chains)
      Dexpace::Recovery::Orchestrator.build(
        transport: transport,
        request_chain: request_chain || Dexpace::Recovery::RequestChain.build(**chains.slice(:steps)),
        response_chain: response_chain ||
          Dexpace::Recovery::ResponseChain.build(**chains.slice(:response_steps, :recovery_steps)),
      )
    end

    def send_through(orchestrator, cancellation: Dexpace::Cancellation.none)
      orchestrator.call(build_request, Dexpace::RequestOptions::EMPTY, cancellation)
    end
  end
  include Orchestrators

  test "is a transport by phase 2's duck type, and exposes its three frozen references" do
    transport = FakeTransport.new(response: build_response)
    request_chain = Dexpace::Recovery::RequestChain.build
    response_chain = Dexpace::Recovery::ResponseChain.build

    orchestrator = orchestrate(transport, request_chain: request_chain,
                                          response_chain: response_chain,)

    assert(Dexpace::Transport.conforms?(orchestrator))
    assert_same(transport, orchestrator.transport)
    assert_same(request_chain, orchestrator.request_chain)
    assert_same(response_chain, orchestrator.response_chain)
  end

  test "a successful send runs the request chain, the transport and the response chain" do
    response = build_response
    transport = FakeTransport.new(response: response)
    log = []
    stamped = ->(request) { request.with(headers: headers_with("X-Step", "ran")) }
    orchestrator = orchestrate(transport, steps: [stamped],
                                          response_steps: [lambda { |resp|
                                            log << :response
                                            resp
                                          }],
                                          recovery_steps: [lambda { |outcome|
                                            log << :recovery
                                            outcome
                                          }],)
    options = Dexpace::RequestOptions::EMPTY
    token = Dexpace::Cancellation.none

    result = orchestrator.call(build_request, options, token)

    assert_same(response, result)
    assert_equal(%i[response recovery], log)
    assert_equal(1, transport.calls.size)
    sent, seen_options, seen_token = transport.calls.first

    assert_equal(["ran"], sent.headers["X-Step"], "the transport receives the folded request")
    assert_same(options, seen_options)
    assert_same(token, seen_token)
  end

  # The defining invariant, driven from the REQUEST side: a throwing request step surfaces as a
  # Failure to a recovery hook, and the transport is never called. A suite that only throws from
  # the transport passes against an orchestrator that wraps the transport call alone.
  test "a before-request throw does not skip after-error handling (RECOV-2)" do
    observed = nil
    transport = FakeTransport.new(response: build_response)
    orchestrator = orchestrate(transport,
                               steps: [->(_) { raise ::IOError, "pre-request explosion" }],
                               recovery_steps: [lambda { |outcome|
                                 observed = outcome.error
                                 outcome
                               }],)

    error = assert_raises(::IOError) { send_through(orchestrator) }

    assert_equal("pre-request explosion", error.message)
    assert_same(error, observed)
    assert_empty(transport.calls, "the transport must not be called when a request step threw")
  end

  test "a transport throw is converted to a Failure the recovery steps observe (RECOV-2)" do
    transport_error = ::StandardError.new("connection dropped")
    observed = nil
    orchestrator = orchestrate(FakeTransport.new(raises: transport_error),
                               recovery_steps: [lambda { |outcome|
                                 observed = outcome
                                 outcome
                               }],)

    caught = assert_raises(::StandardError) { send_through(orchestrator) }

    assert_same(transport_error, caught)
    assert_predicate(observed, :failure?)
    assert_same(transport_error, observed.error)
  end

  test "a transport returning something that is not a Response is a Failure, not a crash" do
    orchestrator = orchestrate(FakeTransport.new(response: "not a response"))

    assert_raises(Dexpace::InvalidArgumentError) { send_through(orchestrator) }
  end

  test "a recovery step can turn a failed send into a response the caller receives" do
    replacement = build_response(200)
    orchestrator = orchestrate(
      FakeTransport.new(raises: ::IOError.new("dropped")),
      recovery_steps: [->(_) { Dexpace::Outcome::Success.build(response: replacement) }],
    )

    assert_same(replacement, send_through(orchestrator))
  end

  # RECOV-10's unwrap, RECOV-11's token, and the two escapes.
  class UnwrapTest < DexpaceTestCase
    include Orchestrators

    # assert_same, never assert_equal: Exception#== is STRUCTURAL (verified fact 6), so
    # assert_equal would pass against an implementation that substituted an equal error, which
    # is exactly what RECOV-10's "no wrapping, no substitution" forbids.
    test "a terminal Failure's error is rethrown unchanged, by identity (RECOV-10)" do
      transport_error = ::StandardError.new("connection dropped")
      orchestrator = orchestrate(FakeTransport.new(raises: transport_error))

      caught = assert_raises(::StandardError) { send_through(orchestrator) }

      assert_same(transport_error, caught)
      assert_equal([], Dexpace.suppressed(caught))
    end

    # The Failure MUST carry an error this test CONSTRUCTED and never raised -- RECOV-10's own
    # named case, "a recovery step constructing the error and returning a Failure". An error a
    # fixture RAISED inside the rescue below already acquired the unrelated exception as its
    # #cause at its own `raise`, and `cause: nil` suppresses the assignment without clearing a
    # pre-existing cause (verified fact 5), so assert_nil would fail against a CORRECT
    # implementation. The caller's own rescue is what makes $! non-nil at the unwrap.
    test "the unwrap attaches no cause while an unrelated exception is in flight (RECOV-10)" do
      constructed = ::StandardError.new("constructed by a recovery step, never raised")
      orchestrator = orchestrate(
        FakeTransport.new(response: build_response),
        recovery_steps: [->(_) { Dexpace::Outcome::Failure.build(error: constructed) }],
      )

      surfaced = begin
        raise "unrelated caller in-flight exception"
      rescue ::StandardError
        begin
          send_through(orchestrator)
        rescue ::StandardError => caught
          caught
        end
      end

      assert_same(constructed, surfaced)
      assert_nil(surfaced.cause, "the unwrap must pass cause: nil, or the caller's $! is assigned")
    end

    # RECOV-11, asserted on the TOKEN and not on the error (P4-17): phase 2's Source#cancel is
    # idempotent and latched, so converting a CancelledError into a Failure cannot swallow the
    # signal, and nothing here re-asserts anything. A test that the Failure carries a
    # CancelledError proves nothing about the signal.
    test "the cancellation signal is still asserted after conversion and unwrap (RECOV-11)" do
      source = Dexpace::Cancellation.source
      source.cancel(:cancelled_explicitly)
      cancel_error = Dexpace::CancelledError.new("wait cancelled")
      observed = nil
      orchestrator = orchestrate(FakeTransport.new(raises: cancel_error),
                                 recovery_steps: [lambda { |outcome|
                                   observed = source.token.cancelled?
                                   outcome
                                 }],)

      caught = assert_raises(Dexpace::CancelledError) do
        send_through(orchestrator, cancellation: source.token)
      end

      assert_same(cancel_error, caught)
      assert(observed, "the token must still answer cancelled? inside the recovery fold")
      assert_predicate(source.token, :cancelled?, "and after the unwrap")
      assert_equal(:cancelled_explicitly, source.token.reason)
    end

    # R6's LoadError case, RETRY-25's rule: a ScriptError from a request step escapes the whole
    # region unconverted and no recovery hook observes it -- the defining invariant's one blind
    # spot, documented on the class and asserted for the case that will actually happen.
    test "the fatal family escapes unconverted and unobserved (RETRY-25)" do
      hook_ran = false
      orchestrator = orchestrate(FakeTransport.new(response: build_response),
                                 steps: [->(_) { raise ::LoadError, "cannot load such file" }],
                                 recovery_steps: [lambda { |outcome|
                                   hook_ran = true
                                   outcome
                                 }],)

      escaped = assert_raises(::LoadError) { send_through(orchestrator) }

      refute(hook_ran, "recovery hooks must not observe a ScriptError")
      assert_equal([], Dexpace.suppressed(escaped))
    end

    # R6, P4-19: a core defect is re-raised by name from the response chain and from the
    # orchestrator's own region alike, never converted into a Failure a step may swallow.
    test "an OutcomeError escapes the orchestrator unconverted (R6, P4-19)" do
      swallow = ->(_) { Dexpace::Outcome::Success.build(response: build_response) }
      from_chain = orchestrate(FakeTransport.new(response: build_response),
                               recovery_steps: [->(_) { "not an outcome" }, swallow],)
      from_step = orchestrate(FakeTransport.new(response: build_response),
                              steps: [->(_) { raise Dexpace::OutcomeError, ::String }],
                              recovery_steps: [swallow],)

      assert_raises(Dexpace::OutcomeError) { send_through(from_chain) }
      assert_raises(Dexpace::OutcomeError) { send_through(from_step) }
    end

    test "a response chain that hands back a non-Outcome is a defect, not a response" do
      chain = Object.new
      def chain.apply(_outcome) = :not_an_outcome
      orchestrator = orchestrate(FakeTransport.new(response: build_response),
                                 response_chain: chain,)

      assert_raises(Dexpace::OutcomeError) { send_through(orchestrator) }
    end

    test "build validates its three collaborators and new is private" do
      transport = FakeTransport.new(response: build_response)
      request_chain = Dexpace::Recovery::RequestChain.build
      response_chain = Dexpace::Recovery::ResponseChain.build
      build = Dexpace::Recovery::Orchestrator.method(:build)

      assert_raises(Dexpace::InvalidArgumentError) do
        build.call(transport: nil, request_chain: request_chain, response_chain: response_chain)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        build.call(transport: :nope, request_chain: request_chain, response_chain: response_chain)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        build.call(transport: transport, request_chain: nil, response_chain: response_chain)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        build.call(transport: transport, request_chain: request_chain, response_chain: nil)
      end
      assert_raises(::NoMethodError) do
        Dexpace::Recovery::Orchestrator.new(transport: transport, request_chain: request_chain,
                                            response_chain: response_chain,)
      end
    end
  end
end
