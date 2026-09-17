# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/invalid_argument_error"
require_relative "http_tracer"

module Dexpace
  module Instrumentation
    # Design §8.1's `CallableAdapter`: the pub/sub bus shape, offered so a consumer whose
    # listener is one `#call(name, payload)` object can receive OBS-28's vocabulary without that
    # shape being the default. Forwards each of the eleven callbacks as its name and a Hash of
    # the arguments under their parameter names, and returns nil from each as the vocabulary
    # does.
    #
    # It allocates one payload Hash per event BY CONSTRUCTION -- that is what the bus shape
    # costs, and it is why the named-method module and not this adapter is the default: OBS-25's
    # no-allocation clause is about the no-op path, which is NULL, and a consumer who installs
    # this adapter has chosen the bus shape and its allocation. It wraps nothing (OBS-30): a
    # raising bus fails the caller's request, as any HTTP tracer's callback would.
    class CallableAdapter
      include HTTPTracer

      # @param callable [#call] the bus, called as `call(name, payload)` per event
      # @raise [InvalidArgumentError] when `callable` does not respond to `#call`
      def initialize(callable)
        unless callable.respond_to?(:call)
          raise InvalidArgumentError, "callable must respond to #call(name, payload)"
        end

        @callable = callable
      end

      # @param (see HTTPTracer#operation_started)
      # @return [nil]
      def operation_started(context)
        @callable.call(:operation_started, { context: context })
        nil
      end

      # @param (see HTTPTracer#operation_succeeded)
      # @return [nil]
      def operation_succeeded(context, response)
        @callable.call(:operation_succeeded, { context: context, response: response })
        nil
      end

      # @param (see HTTPTracer#operation_failed)
      # @return [nil]
      def operation_failed(context, error)
        @callable.call(:operation_failed, { context: context, error: error })
        nil
      end

      # @param (see HTTPTracer#attempt_started)
      # @return [nil]
      def attempt_started(context, attempt)
        @callable.call(:attempt_started, { context: context, attempt: attempt })
        nil
      end

      # @param (see HTTPTracer#attempt_failed)
      # @return [nil]
      def attempt_failed(context, error, next_delay)
        @callable.call(:attempt_failed, { context: context, error: error, next_delay: next_delay })
        nil
      end

      # @param (see HTTPTracer#retries_exhausted)
      # @return [nil]
      def retries_exhausted(context, error)
        @callable.call(:retries_exhausted, { context: context, error: error })
        nil
      end

      # @param (see HTTPTracer#request_url_resolved)
      # @return [nil]
      def request_url_resolved(context, url)
        @callable.call(:request_url_resolved, { context: context, url: url })
        nil
      end

      # @param (see HTTPTracer#connection_acquired)
      # @return [nil]
      def connection_acquired(context, host, port)
        @callable.call(:connection_acquired, { context: context, host: host, port: port })
        nil
      end

      # @param (see HTTPTracer#request_sent)
      # @return [nil]
      def request_sent(context, byte_count)
        @callable.call(:request_sent, { context: context, byte_count: byte_count })
        nil
      end

      # @param (see HTTPTracer#response_headers_received)
      # @return [nil]
      def response_headers_received(context, status, headers)
        @callable.call(
          :response_headers_received, { context: context, status: status, headers: headers },
        )
        nil
      end

      # @param (see HTTPTracer#response_received)
      # @return [nil]
      def response_received(context, byte_count)
        @callable.call(:response_received, { context: context, byte_count: byte_count })
        nil
      end
    end
  end
end
