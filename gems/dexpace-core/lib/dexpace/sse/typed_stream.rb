# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../closeable"
require_relative "../instrumentation/logger"
require_relative "../sse"
require_relative "event"

module Dexpace
  module SSE
    # The typed adapter, §13.6, returned by Stream#typed: every pulled event goes to the
    # caller-supplied mapper as `(event_name, joined_data)` -- the raw `event` field, nil when
    # absent, and the data lines joined with a single "\n", "" when there were none (SSE-33; the
    # join happens HERE and never in the parser, because SSE-8 keeps the raw list) -- and the
    # mapper's answer is one of three outcomes (SSE-34): SKIP drops the event and advances, DONE
    # ends the iteration cleanly and closes the stream without yielding a model for the sentinel
    # event, and anything else -- nil included -- is the decoded value, yielded bare (P7-23).
    #
    # It is NOT a second Closeable: it holds the Stream and delegates #close and #closed? to it,
    # so SSE-23's exactly-one-resource claim survives the typed layer, and it does not include
    # Enumerable -- one view per stream is SSE-26's and SSE-40's single-pass discipline, and
    # Enumerable would hand a caller thirty methods that each silently take the one view. The two
    # consumption shapes mirror Stream's: `#each { |value| }` and `#values -> Enumerator`, both
    # taking the Stream's one view, so a caller cannot take a second view by switching shapes.
    #
    # Decoding is lazy and per element (SSE-35): the mapper runs inside the pull, so a partial
    # consume decodes only the events taken, and the typed layer pulls only as many raw events as
    # one element needs to drain SKIPs (SSE-39). A mapper that raises propagates at that pull,
    # but the resource is released first and a release failure rides on the mapper error's
    # suppressed trail (SSE-36) -- through Dexpace.close_quietly(stream, onto:), which silently
    # no-ops on a FROZEN primary (P4-13), the same caveat as Stream's own failure path. A DONE
    # closes through the quiet route with the stream's logger, so a release failure there is
    # reported out of band and swallowed, never thrown over the values already delivered (SSE-30).
    #
    # Core recognises no done-sentinel string and no error envelope of its own (SSE-37): whatever
    # convention a generated SDK follows lives in the mapper it supplies.
    class TypedStream
      private_class_method :new

      def initialize(stream:, mapper:, logger:)
        @stream = stream
        @mapper = mapper
        @logger = logger
      end

      # The block form: every decoded value to the block, in the underlying Stream's own scope,
      # with its release on every exit.
      #
      # @yieldparam value [Object] the mapper's decoded value
      # @return [nil]
      # @raise [Dexpace::SSE::StreamStateError] when the stream's one view was already taken or
      #   the stream is closed (SSE-26, SSE-27)
      def each(&block)
        @stream.each do |event|
          break if deliver(event, &block) == :done
        end
        nil
      end

      # The external form: a lazy single-pass Enumerator of decoded values over the Stream's one
      # view, taken now (SSE-40). An abandoned enumerator releases nothing; #close is the remedy.
      #
      # @return [Enumerator]
      # @raise [Dexpace::SSE::StreamStateError] as for #each
      def values
        to_enum(:drive_values, @stream.events)
      end

      # Delegates to the Stream: the typed view owns no resource of its own (SSE-23).
      #
      # @return [nil]
      def close
        @stream.close
      end

      # Delegates to the Stream.
      def closed?
        @stream.closed?
      end

      private

      # SSE-33's call shape, and the one join in the subsystem.
      def map(event)
        @mapper.call(event.event, event.data.join("\n"))
      end

      # One event through the mapper: yields a value, skips a SKIP, and on DONE closes the stream
      # quietly and answers :done so the caller stops; :more otherwise. Identity, never ==.
      def deliver(event)
        outcome = map(event)
        return :more if outcome.equal?(SKIP)

        if outcome.equal?(DONE)
          Dexpace.close_quietly(@stream, logger: @logger)
          return :done
        end

        yield outcome
        :more
      end

      # The external drive: raw events off the Stream's own enumerator, the mapper run per pull.
      # A mapper raising here runs on the consumer's side of that enumerator, so the release is
      # this layer's (SSE-36); a raw read failure arrives already released by the Stream (SSE-29)
      # and the quiet close below is then a no-op on the flipped latch.
      def drive_values(raw, &)
        while (event = next_raw(raw))
          break if deliver(event, &) == :done
        end
        nil
      rescue ::Exception => error # rubocop:disable Lint/RescueException -- release, then re-raise unchanged
        Dexpace.close_quietly(@stream, onto: error)
        raise
      end

      def next_raw(raw)
        raw.next
      rescue ::StopIteration
        nil
      end
    end
  end
end
