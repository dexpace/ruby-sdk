# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "../failure"
require_relative "../assertion"
require_relative "../scripts"

module Dexpace
  module Conformance
    module TransportSuite
      # The helpers every assertion group's functions share: the one way a check fails, the
      # request-building shorthands, the timing and error-capturing wrappers, and the registry
      # builder each group's ASSERTIONS table goes through. Nothing here names an adapter, a
      # native client class, a thread or a reactor (8a's R16). A private_constant of
      # TransportSuite.
      module Checks
        extend self

        # How long an assertion waits for the fixture to observe a connection closing, before
        # calling the connection unreleased. A bound, so a transport that never releases fails
        # the assertion rather than hanging the run; generous, because the server observes a close
        # in milliseconds and CI load is the only thing that stretches it.
        CLOSE_WAIT_SECONDS = 2.0

        # The one way an assertion fails: nothing when the condition holds, a Failure carrying the
        # ids and the two values otherwise.
        #
        # @param condition [Object] truthy when the check holds
        # @param message [String]
        # @param ids [Array<String>] the requirement ids the check is for
        # @param expected [Object]
        # @param actual [Object]
        # @return [nil]
        # @raise [Failure]
        def check(condition, message, ids:, expected:, actual:)
          return nil if condition

          raise Failure.new(message, expected: expected, actual: actual, requirement_ids: ids)
        end

        # #check for the common shape: what was seen must equal what was expected.
        #
        # @param seen [Object]
        # @param expected [Object]
        # @param message [String]
        # @param ids [Array<String>]
        # @return [nil]
        def expect(seen, expected, message, ids:)
          check(seen == expected, message, ids: ids, expected: expected, actual: seen)
        end

        # Suite contract clause 5: a failure carrying no HTTP response answers #retryable? true.
        #
        # @param error [Exception, nil]
        # @return [Boolean]
        def retryable_failure?(error)
          !error.nil? && error.respond_to?(:retryable?) && error.retryable? == true
        end

        # A group's frozen registry, from rows of `[ids, name, function]` where `function` names
        # a public method of `group` taking the case -- one row per assertion, so a group's table
        # reads as its index.
        #
        # @param group [Module] the group module
        # @param rows [Array<Array>] `[ids, name, function]` triples
        # @return [Array<Assertion>] frozen
        def registry(group, rows)
          rows.map do |ids, name, function|
            Assertion.build(ids: Array(ids), name: name,
                            body: ->(kase) { group.public_send(function, kase) },)
          end.freeze
        end

        # @param pairs [Hash{String => String}] header name to value
        # @return [Dexpace::Headers] an outbound Headers
        def headers(pairs)
          builder = Dexpace::Headers.builder
          pairs.each { |name, value| builder.add(name, value) }
          builder.build
        end

        # @return [Dexpace::MediaType] application/json
        def json
          Dexpace::MediaType.parse("application/json")
        end

        # @param string [String] the bytes
        # @param media_type [Dexpace::MediaType, nil]
        # @return [Dexpace::BytesBody] a replayable body
        def bytes_body(string, media_type: nil)
          Dexpace::Body.bytes(string.b, media_type: media_type)
        end

        # A SINGLE-USE body (phase 3b's ChunkedBody is never replayable, P3-19) over one chunk,
        # counting how many times it was pulled -- what TRANSPORT-2, TRANSPORT-17 and TRANSPORT-18
        # ask about a body that must never be written twice.
        #
        # @param payload [String] the one chunk
        # @return [Array(Dexpace::Body, #call)] the body and a callable answering the pull count
        def single_use_body(payload)
          pulls = 0
          chunked = Object.new
          chunked.define_singleton_method(:each) do |&block|
            pulls += 1
            block.call(payload.b)
          end
          [Dexpace::Body.chunked(chunked, content_length: payload.bytesize), -> { pulls }]
        end

        # @param timeout [Numeric, nil]
        # @param max_retries [Integer, nil]
        # @return [Dexpace::RequestOptions]
        def options(timeout: nil, max_retries: nil)
          builder = Dexpace::RequestOptions.builder
          builder.timeout = timeout unless timeout.nil?
          builder.max_retries = max_retries unless max_retries.nil?
          builder.build
        end

        # The last request the fixture recorded, or a Failure naming the ids when it recorded none.
        #
        # @param kase [TransportCase]
        # @param ids [Array<String>]
        # @return [WireServer::RecordedRequest]
        def last_request(kase, ids:)
          recorded = kase.wire.requests.last
          check(recorded, "no request reached the wire", ids: ids, expected: "one request",
                                                         actual: kase.wire.requests.size,)
          recorded
        end

        # Waits, bounded, for the fixture to see one more connection finish, then checks it did.
        #
        # @param kase [TransportCase]
        # @param ids [Array<String>]
        # @param message [String]
        # @return [nil]
        def check_connection_released(kase, ids:, message:)
          released = kase.wire.await_closed_connection(timeout: CLOSE_WAIT_SECONDS)
          check(released, message, ids: ids, expected: "a close within #{CLOSE_WAIT_SECONDS} s",
                                   actual: "#{kase.wire.closed_connections} closed",)
        end

        # A thread that cancels `source` the instant the server reports the client blocked waiting
        # for the head -- through the script's hook and a Queue#pop, never a guessed delay -- for
        # TRANSPORT-3's send-path cancellation.
        #
        # @param kase [TransportCase]
        # @param source [Dexpace::Cancellation::Source]
        # @return [Thread] the canceller, for the assertion to join
        def cancel_when_blocked(kase, source)
          blocked = ::Thread::Queue.new
          kase.wire(script: Scripts.hang_before_headers(on_request_read: -> { blocked.push(true) }))
          ::Thread.new do
            blocked.pop
            source.cancel(:conformance_cancel)
          end
        end

        # One POST of a single-use body against a server that drops the first connection: whether
        # the send raised a retryable failure, how many connections the server saw and how many
        # times the body was pulled -- the measurement TRANSPORT-2 and TRANSPORT-18 both read.
        #
        # @param kase [TransportCase]
        # @return [Hash{Symbol => Object}] `raised:`, `connections:`, `pulls:`
        def dropped_first_attempt(kase)
          kase.wire(script: Scripts.fail_first_connection_then_succeed("ok"))
          body, pulls = single_use_body("payload")
          error = error_from do
            kase.settle(kase.transport, kase.request(method: "POST", body: body))
          end
          { raised: retryable_failure?(error), connections: kase.wire.connections,
            pulls: pulls.call, }
        end

        # Each measured duration inside its own band, in order: TRANSPORT-5's "each bounded by
        # its own value", asserted over a list of calls.
        #
        # @param timings [Array<Float>]
        # @param bands [Array<Range>]
        # @return [Boolean]
        def within_bands?(timings, bands)
          timings.each_with_index.all? { |took, i| bands.fetch(i).cover?(took) }
        end

        # The error a send raised (nil when it returned) and how long it took, together.
        #
        # @yield the send under test
        # @return [Array(StandardError?, Float)]
        def timed_error(&block)
          error = nil
          took = elapsed { error = error_from(&block) }
          [error, took]
        end

        # @yield the send under test
        # @return [StandardError, nil] what it raised, or nil when it returned
        def error_from
          yield
          nil
        rescue ::StandardError => error
          error
        end

        # @yield the work to time
        # @return [Float] seconds, off the monotonic clock
        def elapsed
          started = monotonic
          yield
          monotonic - started
        end

        # @return [Float] Process.clock_gettime(Process::CLOCK_MONOTONIC)
        def monotonic
          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        end
      end
      private_constant :Checks
    end
  end
end
