# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-28's HTTP-shaped tracer event vocabulary, "richer than start/end": eleven callbacks in
    # three groups -- the operation lifecycle, the per-attempt events and the transport
    # milestones -- every one defaulting to a no-op, so "adding a new event is a non-breaking
    # change and implementers override only what they need" is a mechanism rather than a
    # docstring. A module, not a base class: Ruby has single inheritance and an implementer may
    # already have a superclass. A module, not a bare duck type: a duck type gives no defaults,
    # and under OBS-30's no-wrapping rule a missing method is a NoMethodError in the caller's
    # request path. Positional arguments only, on the stack, so a callback on the frozen NULL
    # allocates nothing (OBS-25; observability/4044a5c7).
    #
    # OBS-29's ordering contract binds an IMPLEMENTER'S EMITTER, not this module: operation
    # started fires once at the start; operation succeeded and operation failed are mutually
    # exclusive and each fires exactly once at the end; attempt events may fire many times;
    # retries exhausted, when it fires, is immediately followed by operation failed carrying the
    # SAME error object; and one tracer instance corresponds 1:1 to one logical operation
    # lifecycle, created by its factory per operation. ordering_test.rb drives a conformant
    # emitter through both a succeeding and a retry-exhausted operation, which is the
    # requirement's own conformance clause. The per-attempt group is emitted by phase 6a's three
    # retry drivers (Resilience::RetryStep, ::AsyncRetryStep and ::RecoveryRetry), through the
    # tracer their `http_tracer_factory:` produces once per operation -- called with the
    # Pipeline::Cursor on the stage stack and with the Dexpace::Request on the recovery stack --
    # and retries_exhausted fires there only when a RETRYABLE failure met a spent budget, never
    # for a failure that was never retryable (ordering_test.rb's third case). The transport
    # milestones and the operation-lifecycle triple are emitted by nothing in v1 (phase 10's
    # inbound list; docs/first-release.md's behavioural-asymmetries entry), which OBS-29's own
    # last sentence anticipates: "pipeline/transport wiring to emit it is a follow-up" (R14).
    # The interface _HTTPTracer, which 5c deliberately did not declare, arrived with the wiring
    # (6a's R3) in this file's sig/ mirror.
    #
    # OBS-30 binds every implementation: each callback is safe to invoke concurrently and from
    # a transport thread other than the caller's, and never throws -- the runtime does not
    # defensively catch these callbacks, so a raise here fails the caller's request.
    module HTTPTracer
      # rubocop:disable Lint/UnusedMethodArgument -- OBS-28: every event method defaults to a
      # no-op; the parameter names are the contract phases 6 and 8 emit against.

      # The operation lifecycle group: fires once, at the start (OBS-29).
      #
      # @param context [Object] the operation's context
      # @return [nil]
      def operation_started(context)
        nil
      end

      # Fires exactly once at the end, and never with operation_failed (OBS-29).
      #
      # @param context [Object] the operation's context
      # @param response [Object] the terminal response
      # @return [nil]
      def operation_succeeded(context, response)
        nil
      end

      # Fires exactly once at the end, and never with operation_succeeded; immediately after
      # retries_exhausted when that fired, with the same error object (OBS-29).
      #
      # @param context [Object] the operation's context
      # @param error [Exception] the error the operation failed with
      # @return [nil]
      def operation_failed(context, error)
        nil
      end

      # The per-attempt group: may fire many times per operation (OBS-29). Phase 6a's retry
      # step is the emitter.
      #
      # @param context [Object] the operation's context
      # @param attempt [Integer] the attempt number, from 1
      # @return [nil]
      def attempt_started(context, attempt)
        nil
      end

      # An attempt failed and another will follow after `next_delay`.
      #
      # @param context [Object] the operation's context
      # @param error [Exception] the attempt's error
      # @param next_delay [Numeric] the delay before the next attempt
      # @return [nil]
      def attempt_failed(context, error, next_delay)
        nil
      end

      # No further attempt will be made; operation_failed follows immediately with the same
      # error object (OBS-29).
      #
      # @param context [Object] the operation's context
      # @param error [Exception] the last attempt's error
      # @return [nil]
      def retries_exhausted(context, error)
        nil
      end

      # The transport milestones group: phase 8's adapters are the emitters.
      #
      # @param context [Object] the operation's context
      # @param url [Object] the resolved request URL
      # @return [nil]
      def request_url_resolved(context, url)
        nil
      end

      # A connection was acquired, with the peer named.
      #
      # @param context [Object] the operation's context
      # @param host [String] the peer host
      # @param port [Integer] the peer port
      # @return [nil]
      def connection_acquired(context, host, port)
        nil
      end

      # The request was written, with its size.
      #
      # @param context [Object] the operation's context
      # @param byte_count [Integer] the bytes sent
      # @return [nil]
      def request_sent(context, byte_count)
        nil
      end

      # The response head arrived.
      #
      # @param context [Object] the operation's context
      # @param status [Integer] the response status code
      # @param headers [Object] the response headers
      # @return [nil]
      def response_headers_received(context, status, headers)
        nil
      end

      # The response body was fully received, with its size.
      #
      # @param context [Object] the operation's context
      # @param byte_count [Integer] the bytes received
      # @return [nil]
      def response_received(context, byte_count)
        nil
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end

    # The class behind NULL: includes the vocabulary and adds nothing.
    class NullHTTPTracer
      include HTTPTracer
    end
    private_constant :NullHTTPTracer

    # Design §8.1's `Dexpace::Instrumentation::NULL`: the one frozen no-op HTTP tracer, the value
    # an unconfigured slot holds, and OBS-25's "a no-op HTTP-tracer" -- every callback on it
    # allocates nothing. Public because §8.1 names it and because a conformance assertion names
    # it by a qualified reference.
    NULL = NullHTTPTracer.new.freeze
  end
end
