# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "stage"
require_relative "../error/pipeline_error"
require_relative "../error/invalid_argument_error"
require_relative "../instrumentation/bundle"

module Dexpace
  class Pipeline
    # The per-call, per-invocation execution handle every step is given as its second argument
    # (PIPE-10): the position in the runtime's frozen entry table, the in-flight request, the
    # caller's immutable options, the cancellation token, and the (stage, key) state map. A class
    # rather than a Data, because it owns the one piece of per-call mutable state in the
    # subsystem, its single-use latch.
    #
    # One class serves both runtimes (P4-30). What differs is the driver behind it -- a
    # private_constant SyncDriver or AsyncDriver, supplied by the runtime -- so #call returns a
    # Dexpace::Response under the first and a Dexpace::Async::Future under the second; the RBS
    # types it `untyped` and the _Step/_AsyncStep interfaces carry the real types (plan open
    # question 7).
    #
    # .build is public and validating, and it produces the ROOT cursor: bound to no entry
    # (owner index -1), it advances INTO entry 0 and cannot fork. Every cursor a step is handed
    # is made by the driver, bound to the entry it is invoking, and that binding -- not anything
    # the step says -- is what #fork and #state are gated on (R10). A forged cursor built through
    # `send` or `const_get` lands in the forger's own hands and never reaches a step, because a
    # step never constructs the cursor it is given; that is why the residual holes phase 1's P8
    # names cost nothing here, and no proof that they are closed is attempted.
    #
    # It holds no lock (P4-33). It is created per step invocation, handed to exactly one step and
    # never published, so a Thread::Mutex would cost an allocation on every step of every call and
    # put a per-fiber-owned, non-reentrant lock in the hot path. The price is that the reuse
    # guard is sequential-only; see #call.
    #
    # Per-call state lives HERE and is passed as an argument, never read from ambient storage
    # (PIPE-11): not Fiber[], not Thread.current[]. A step that spawns a thread or a fiber hands
    # it the cursor explicitly; nothing is inherited.
    #
    # #bundle is phase 6a's widening (its Task 8): the per-call instrumentation bundle CTX-14
    # names, seeded by the one optional `bundle:` keyword on Pipeline#call and AsyncPipeline#call,
    # carried across #fork exactly as #options is, and Bundle::NONE when nothing seeded it. It is
    # what lets 5b's instrumentation step honour the reconciled precedence's first clause -- the
    # request's own bundle before the step's constructor keyword -- which had no implementation
    # path in phase 5 (4c consumed nothing of 4a; Request carries no bundle; PIPE-11 forbids
    # ambient carriage). A read-only member and a widening under NFR-4: no existing signature
    # moved, and a caller who passes nothing gets exactly what phase 5 gave it. It is NOT the
    # retry step's HTTP-tracer source: OBS-29's per-operation tracer is a different kind of
    # object from Bundle#tracer_factory (P6-7), and the retry drivers take their own factory,
    # called with the cursor itself.
    class Cursor
      # One shared frozen hash for a stage nothing wrote, and one for the root cursor's map, so
      # neither the empty read nor the root allocates (verified fact 4).
      slot = {} #: Hash[untyped, untyped]
      EMPTY_SLOT = slot.freeze
      state = {} #: Hash[Stage, Hash[untyped, untyped]]
      EMPTY_STATE = state.freeze
      private_constant :EMPTY_SLOT, :EMPTY_STATE

      private_class_method :new

      # @return [Dexpace::Request] the current in-flight request (PIPE-16)
      attr_reader :request
      # @return [Dexpace::RequestOptions] the caller's per-call options, the same frozen object at
      #   every position and across every fork (PIPE-17)
      attr_reader :options
      # @return [Dexpace::Cancellation] the token a step checks at every resume point and the
      #   terminal dispatch is handed
      attr_reader :cancellation
      # @return [Dexpace::Instrumentation::Bundle] the per-call correlation bundle, the same
      #   frozen object at every position and across every fork; Bundle::NONE when the call
      #   seeded none (CTX-14, phase 6a's Task 8)
      attr_reader :bundle

      # The root cursor for one send: bound to no entry, at position 0, with empty state. There is
      # no owner_index:, position: or state: keyword here and a caller cannot name one -- those
      # are the driver's.
      #
      # @param drive [Object] the runtime's private driver
      # @param request [Dexpace::Request]
      # @param options [Dexpace::RequestOptions]
      # @param cancellation [Dexpace::Cancellation]
      # @param bundle [Dexpace::Instrumentation::Bundle] the per-call bundle; NONE by default
      # @return [Dexpace::Pipeline::Cursor]
      # @raise [Dexpace::InvalidArgumentError] for a bundle: that is not a Bundle
      def self.build(drive:, request:, options:, cancellation:,
                     bundle: Instrumentation::Bundle::NONE)
        unless bundle.is_a?(Instrumentation::Bundle)
          raise InvalidArgumentError,
                "bundle: takes an Instrumentation::Bundle, got #{bundle.class}"
        end

        new(drive: drive, owner_index: -1, position: 0, request: request, options: options,
            cancellation: cancellation, bundle: bundle, state: EMPTY_STATE,)
      end

      def initialize(drive:, owner_index:, position:, request:, options:, cancellation:, bundle:,
                     state:)
        @drive = drive
        @owner_index = owner_index
        @position = position
        @request = request
        @options = options
        @cancellation = cancellation
        @bundle = bundle
        @state = state
        @spent = false
      end

      # Whether #call has been used. What makes PIPE-15's defect observable without rescuing, and
      # what a step asks before choosing between #call and #fork.
      def spent? = @spent

      # Whether #fork would succeed: the owning entry's stage is a non-terminal pillar (R10) and
      # this cursor's own drive has not been spent (P4-39). Reads the same frozen entry table
      # #fork gates on, so a step can ask rather than rescue.
      def may_fork? = !@spent && !owner_stage.nil?

      # The frozen state written into `stage`'s slot by the pillar step that forked this cursor
      # or one of its ancestors (R11, P4-28); one shared frozen empty hash for a stage nothing
      # wrote. A non-Stage is refused rather than read as an empty slot.
      #
      # @param stage [Dexpace::Pipeline::Stage]
      # @return [Hash] frozen
      # @raise [Dexpace::InvalidArgumentError] for a non-Stage
      def state(stage)
        unless stage.is_a?(Stage)
          raise InvalidArgumentError, "state takes a Stage, got #{stage.class}"
        end

        @state.fetch(stage, EMPTY_SLOT)
      end

      # PIPE-12, PIPE-13. Advances to the next entry and invokes it; past the last entry the driver
      # dispatches to the terminal transport, threading the caller's options (PIPE-17). PIPE-14's
      # substitution sticks by construction: the child cursor carries the object passed here, and
      # the original is retained nowhere on the drive.
      #
      # Single-use. **The reuse guard is sequential-only** (P4-33): a second sequential call
      # always raises, a second CONCURRENT call sometimes does not -- eight threads through one
      # unsynchronised latch let more than one caller past on 29 of 2000 runs on 3.2.11 and 0 of
      # 2000 on 3.4.10 and 4.0.6. Handing one cursor to two threads is already the defect PIPE-15
      # names; do not read the raise as a concurrency guard.
      #
      # @param request [Dexpace::Request] the request to drive with; the in-flight one by default
      # @return [Dexpace::Response, Dexpace::Async::Future] per the runtime's driver
      # @raise [Dexpace::PipelineError] on a second invocation
      def call(request = @request)
        if @spent
          raise PipelineError, "cursor has already been invoked and cannot be reused (PIPE-15)"
        end

        @spent = true
        @drive.advance(position: @position, request: request, options: @options,
                       cancellation: @cancellation, bundle: @bundle, state: @state,)
      end

      # PIPE-15, PIPE-16. A fresh cursor at the SAME position as this one, carrying the current
      # in-flight request and the same frozen options object, that advances independently.
      #
      # Three rules a phase-6 pillar author has to know, and each is a raise rather than a
      # comment:
      #
      # 1. Only a non-terminal pillar may fork (R10). The gate reads the RUNTIME's frozen entry
      #    table at the owner index, never the step's own #stage -- a forged step that answers
      #    Stages::REDIRECT while sitting in PRE_REDIRECT gets nothing, because nothing asks it.
      # 2. **#call and #fork are disjoint on one cursor (P4-39).** A step either drives once
      #    through #call and never forks, or forks for EVERY drive including the first and never
      #    calls #call. PIPE-15's own wording describes the reference's mixed shape -- drive 1 on
      #    the handle, drives 2..n on copies -- and this port does not use it: forking for drive
      #    1 too is what makes hop 1 and hop n the same object and what gives a pillar's first
      #    drive a stage slot to write into. Forking earlier than PIPE-15 requires is strictly
      #    inside it; forking a spent cursor is PIPE-15's defect under the fork's name.
      # 3. `state:` lands in the OWNER's own stage slot, chosen from the entry table and never
      #    named by the caller (R11, P4-28), merged key by key over what the slot already held.
      #    REDIR-11's marker expires for free: hop 2 is a fork of the same parent, not of hop 1's
      #    fork, so it starts from the parent's slot and never sees hop 1's.
      #
      # PIPE-40 travels with this handle: a re-driving step closes each superseded intermediate
      # response before the next drive, never closes the one it hands back, and returns the
      # in-flight response unclosed on an abandoned re-drive. The reuse guard #call carries is
      # sequential-only; see #call.
      #
      # @param state [Hash, nil] pairs to merge into the owner's stage slot
      # @return [Dexpace::Pipeline::Cursor]
      # @raise [Dexpace::PipelineError] on a spent cursor, a slot stage, or the root cursor
      # @raise [Dexpace::InvalidArgumentError] for a state: that is not a Hash
      def fork(state: nil)
        if @spent
          raise PipelineError,
                "cursor is spent and cannot be forked; #call and #fork are disjoint (PIPE-15)"
        end
        unless state.nil? || state.is_a?(::Hash)
          raise InvalidArgumentError, "state: takes a Hash, got #{state.class}"
        end

        stage = owner_stage
        refuse_fork if stage.nil?

        Cursor.send(:new, drive: @drive, owner_index: @owner_index, position: @position,
                          request: @request, options: @options, cancellation: @cancellation,
                          bundle: @bundle, state: merged_state(stage, state),)
      end

      private

      # The owning entry's stage when it is a non-terminal pillar; nil for a slot, the terminal
      # stage, or the root cursor.
      def owner_stage
        return nil if @owner_index.negative?

        stage = @drive.entry_at(@owner_index).stage
        stage.pillar? && !stage.terminal? ? stage : nil
      end

      def refuse_fork
        if @owner_index.negative?
          raise PipelineError, "the root cursor is bound to no entry and cannot fork (PIPE-15)"
        end

        name = @drive.entry_at(@owner_index).stage.name
        raise PipelineError, "stage #{name} is not a configurable pillar and cannot fork (PIPE-15)"
      end

      # Verified fact 4: merge on a frozen receiver returns a new hash and leaves the receiver
      # untouched, and the inner slot is frozen independently the moment it is created, because
      # freeze is shallow. An empty write allocates nothing.
      def merged_state(stage, state)
        return @state if state.nil? || state.empty?

        slot = @state.fetch(stage, EMPTY_SLOT).merge(state).freeze
        @state.merge(stage => slot).freeze
      end
    end
  end
end
