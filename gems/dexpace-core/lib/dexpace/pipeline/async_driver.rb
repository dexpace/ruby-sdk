# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "cursor"
require_relative "../async/completer"
require_relative "../async/future"
require_relative "../error/seam_error"

module Dexpace
  class Pipeline
    # The asynchronous half of what differs between the two runtimes (P4-30): the same advance as
    # SyncDriver, with PIPE-29/PIPE-30's normalisation around every step invocation and around the
    # terminal dispatch. A private_constant with a sig/ mirror, no manifest row and no suite of
    # its own; its behaviour is asserted in async_pipeline_test.rb.
    #
    # PIPE-30 at the call site no phase-2 object reaches. A step's async entry point that raises
    # synchronously -- a NoMethodError, an argument-validation error PIPE-29 permits, anything in
    # StandardError -- becomes an exceptionally-completed future, so one step's mistake cannot
    # break the pipeline's async contract; the runtime's obligation is unconditional, and
    # PIPE-29's permission is a statement about what a step author may do, not a hole in it. The
    # fatal family propagates synchronously through an ABSENT rescue arm rather than a re-raising
    # one: only StandardError is rescued, so a ScriptError -- a NotImplementedError, or the
    # LoadError of a step that lazily requires something absent -- escapes #call, the same line
    # phase 4b drew for RECOV-2, reached here independently. The three lines are the pipeline
    # layer's own and call nothing in Dexpace::Recovery, even though the rule is the same rule:
    # sharing the code would make this layer's error handling a function of the recovery
    # layer's, which spec §8.3's two-layer prohibition forbids.
    #
    # A step's future is returned AS IS. Nothing is re-wrapped in a second Completer, so a
    # failure reaches the caller as the identical object (there is nothing to unwrap), a
    # cancellation reaches the step's own producer directly, and a settled step costs no
    # allocation beyond the cursor. What a step must return is a Dexpace::Async::Future: anything
    # else fails the drive with Dexpace::SeamError, the mirror of Bridge::SyncOver's check on the
    # transport it wraps, because Step.conforms? cannot see a return type (P4-30's cost) and a
    # sync step installed through #build_async would otherwise hand a Response to a caller
    # expecting a future.
    class AsyncDriver
      def initialize(pipeline)
        @pipeline = pipeline
      end

      # The entry at `index`, what Cursor#fork and #may_fork? gate on (R10).
      def entry_at(index) = @pipeline.entries.fetch(index)

      # PIPE-13 on the async side: the step's future, or the transport's, or a future failed with
      # whatever the invocation raised (PIPE-30).
      def advance(position:, request:, options:, cancellation:, bundle:, state:)
        entries = @pipeline.entries
        return dispatch(request, options, cancellation) if position >= entries.size

        normalise(terminal: false) do
          cursor = Cursor.send(:new, drive: self, owner_index: position, position: position + 1,
                                     request: request, options: options,
                                     cancellation: cancellation, bundle: bundle, state: state,)
          entries.fetch(position).step.call(request, cursor)
        end
      end

      # The terminal transport hop, normalised: PIPE-30 names "the empty-pipeline transport
      # dispatch" explicitly, and AsyncPipeline#call reaches this directly for it so the empty
      # branch allocates no cursor (PIPE-9).
      def dispatch(request, options, cancellation)
        normalise(terminal: true) { @pipeline.transport.call(request, options, cancellation) }
      end

      private

      # The one rescue region of the async runtime: StandardError only, so the fatal family passes
      # through an absent arm. The block's result is the future when it is one, and a
      # SeamError-failed future otherwise.
      def normalise(terminal:)
        result = yield
        return result if result.is_a?(Dexpace::Async::Future)

        source = terminal ? "an async transport" : "an async step"
        failed(SeamError.new("#{source} must return a Dexpace::Async::Future, got #{result.class}"))
      rescue ::StandardError => error
        failed(error)
      end

      # An already-failed future carrying `error`, the identical object (PIPE-30, SEAM-18).
      def failed(error)
        completer = Dexpace::Async::Completer.new
        completer.fail(error)
        completer.future
      end
    end
    private_constant :AsyncDriver
  end
end
