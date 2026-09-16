# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "cursor"

module Dexpace
  class Pipeline
    # The synchronous half of what differs between the two runtimes (P4-30): how a step is invoked
    # and how the terminal transport is reached. A private_constant -- it is reached through the
    # driver_class: argument Builder hands each runtime's constructor, never named by a caller --
    # with a sig/ mirror for the strict Steep target and no manifest row, no YARD-gate entry and
    # no test mirror of its own: its behaviour is asserted at its call sites, in cursor_test.rb
    # and pipeline_test.rb.
    #
    # It holds the runtime and nothing else, and reads the runtime's frozen entry table and
    # transport reference on every advance (PIPE-10): there is no per-driver state to share.
    class SyncDriver
      def initialize(pipeline)
        @pipeline = pipeline
      end

      # The entry at `index`, what Cursor#fork and #may_fork? gate on (R10).
      def entry_at(index) = @pipeline.entries.fetch(index)

      # PIPE-13: invoke the entry at `position` with a cursor bound to it, or -- past the last
      # entry -- dispatch to the terminal transport with the in-flight request, the caller's
      # options and the token (PIPE-17).
      def advance(position:, request:, options:, cancellation:, state:)
        entries = @pipeline.entries
        return @pipeline.transport.call(request, options, cancellation) if position >= entries.size

        # Cursor.new is private; this is the one place a step's cursor is made (R10: bound to the
        # entry it is invoking, at the position after it).
        cursor = Cursor.send(:new, drive: self, owner_index: position, position: position + 1,
                                   request: request, options: options, cancellation: cancellation,
                                   state: state,)
        entries.fetch(position).step.call(request, cursor)
      end
    end
    private_constant :SyncDriver
  end
end
