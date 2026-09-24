# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Keys::EVENT and Events::INSTRUMENTATION_SHUTDOWN both live in this one file.
require "dexpace/instrumentation/keys"
require_relative "vacuous"

module Dexpace
  module Conformance
    # What an ExecutorSuite assertion receives. The executor is a FACTORY, never a constant --
    # dexpace-conformance declares dexpace-core and nothing else, so it can name no adapter.
    #
    # The event recorder is built ONCE PER CASE and passed into the factory as an `events:`
    # setting, never shared across a run: Runner builds a fresh case per assertion, so an earlier
    # assertion's shutdown event cannot be counted by a later one. That is testing/4ef070df
    # applied to a fixture the SUITE constructs rather than one a test writes, and it is the
    # defect this phase's own planning run hit -- one shared recorder made the CONFORMING double
    # fail, because three earlier assertions had each built and closed a pool.
    class ExecutorCase
      # XCUT-11's own conformance shape: "invoke one shared instance from MANY threads".
      THREADS = 16

      # The recorder is a SINK, because a sink is where a shutdown is observable. No filed
      # executor in this repository exposes a shutdown counter: the pool reports its shutdown
      # exactly once, from its release, through the injected logger -- and `Event#emit` ends in
      # `@sink.public_send(severity.sink_method) { rendered_record }` with the event tag under
      # `Keys::EVENT`. So the portable observation is the payload this sink receives, and the
      # adapter's `build:` lambda is what wires it into its own logger.
      #
      # Shaped on core's `_Sink` duck type; every predicate answers true, so an INFO-severity
      # shutdown is never filtered by `Logger#enabled?` before it reaches here.
      class EventRecorder
        def initialize
          @payloads = []
          @mutex = ::Thread::Mutex.new
        end

        # @return [Array<Object>] the payloads this sink received, oldest first, as a dup -- a
        #   caller iterating cannot race a close still running on another thread
        def entries = @mutex.synchronize { @payloads.dup }

        # @return [nil] core's `_Sink` duck type; every severity records the same way
        def debug(message = nil, &) = record(message, &)
        # @return [nil]
        def info(message = nil, &) = record(message, &)
        # @return [nil]
        def warn(message = nil, &) = record(message, &)
        # @return [nil]
        def error(message = nil, &) = record(message, &)

        def debug? = true
        def info? = true
        def warn? = true
        def error? = true

        private

        def record(message)
          payload = block_given? ? yield : message
          @mutex.synchronize { @payloads << payload }
          nil
        end
      end
      private_constant :EventRecorder

      # @param build [#call] keyword-taking executor factory; the suite passes `events:` when it
      #   has a recorder and nothing else
      # @param borrow [#call, nil] pool -> a holder that borrows it, or nil when the adapter
      #   exposes no borrowing entry point
      # @param functional [#call, nil] a RESOURCE-FREE implementation for ASYNC-17, or nil
      # @param record_events [Boolean] whether this case builds its OWN event recorder and hands
      #   it to `build:` as `events:`. The recorder's class stays private -- a driver declares
      #   that its factory accepts the keyword rather than constructing one, which keeps a test
      #   double out of the gem's locked public surface.
      def initialize(build:, borrow: nil, functional: nil, record_events: false)
        @build = build
        @borrow = borrow
        @functional = functional
        @recorder = record_events ? EventRecorder.new : nil
      end

      # @return [Object] a fresh executor, wired to this case's recorder when there is one
      def executor
        return @build.call if @recorder.nil?

        @build.call(events: @recorder)
      end

      # @return [Boolean] whether the adapter exposes a borrowing entry point
      def borrowed? = !@borrow.nil?

      # @param pool [Object] the executor to borrow
      # @return [Object] a holder that borrowed it
      def borrowed(pool)
        raise Vacuous, "this adapter exposes no borrowing entry point" if @borrow.nil?

        @borrow.call(pool)
      end

      # @return [Boolean] whether a resource-free implementation was supplied
      def functional? = !@functional.nil?

      # ASYNC-17's subject is a RESOURCE-FREE implementation, supplied separately: asserting the
      # no-op default against a pool that owns a thread would assert the opposite requirement.
      def functional
        raise Vacuous, "no resource-free implementation supplied" if @functional.nil?
        return @functional.call if @recorder.nil?

        @functional.call(events: @recorder)
      end

      # @return [Boolean] whether an event recorder was supplied
      def events? = !@recorder.nil?

      # SEAM-25's "close twice -> executor shut once, one event" needs this and nothing else: how
      # many shutdown payloads the recorder saw. Only the event NAME is read -- the pool's two
      # field keys are its own private constants and are deliberately absent from core's Keys,
      # because the portable assertion needs the event name only.
      #
      # @return [Integer]
      def shutdowns
        recorder = @recorder
        raise Vacuous, "no event recorder supplied to ExecutorSuite.run" if recorder.nil?

        recorder.entries.count { |payload| shutdown?(payload) }
      end

      private

      def shutdown?(payload)
        payload.is_a?(::Hash) &&
          payload[Dexpace::Instrumentation::Keys::EVENT] ==
            Dexpace::Instrumentation::Events::INSTRUMENTATION_SHUTDOWN
      end
    end
  end
end
