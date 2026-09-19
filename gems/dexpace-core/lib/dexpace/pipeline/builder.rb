# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../builder"
require_relative "stage"
require_relative "stages"
require_relative "step"
require_relative "entry"
require_relative "sync_driver"
require_relative "async_driver"
require_relative "../transport"
require_relative "../async_transport"
require_relative "../error/pipeline_error"
require_relative "../error/seam_error"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Pipeline
    # The mutable composition engine for both runtimes (PIPE-4, PIPE-7, PIPE-18; P4-30): staging,
    # pillar exclusivity, the four surgical edits, the two all-or-nothing bulk paths and the
    # flattening are ONE implementation, and #build and #build_async read one bucket table. That
    # is PIPE-28's "MUST NOT each re-derive ordering independently" satisfied by there being one
    # deriver rather than by two derivers agreeing. Phase 1's builder shape, because the
    # validation is cross-field (SEAM-29's contract, included as Dexpace::Builder).
    #
    # Where a step's stage assignment lives (R10): the builder records it at install time and it
    # is the authority. A step MAY declare #stage; when it does, an omitted `stage:` takes the
    # declaration, an agreeing one is accepted, and a disagreeing one is rejected rather than
    # silently resolved. A step that declares nothing must be given `stage:` -- a lambda cannot
    # declare -- and on a surgical edit the stage is REQUIRED rather than inferred from the
    # anchor, because inferring it would make PIPE-18's own cross-stage rejection unreachable for
    # exactly the step shape design §5.1 guarantees is legal. #stage is read once, here, and
    # never again: the runtime consults its frozen entry table and nothing the step says.
    #
    # Flattening re-derives from the stage table, never from an accumulated order (PIPE-22):
    # #entries walks Stages::ALL, skipping SEND, so the order after any edit is the order the
    # same step set would have from scratch because there is nothing else it could be.
    #
    # Pillar collisions compare by #equal?, never == (PIPE-5, PIPE-6): core's models define value
    # equality, so == on two structurally identical steps would report them the same and
    # silently swallow a genuine collision -- the trap CTX-9 sets in design §5.4, arriving here.
    #
    # A builder is single-threaded by construction and holds no lock, exactly as phase 1's
    # builders are; the runtime it produces needs none either, being immutable (PIPE-10).
    class Builder # rubocop:disable Metrics/ClassLength -- one deriver for both runtimes by design (P4-30, PIPE-28); see above
      include Dexpace::Builder

      # PIPE-35 FLATTEN: a new builder holding the pipeline's entries AND its transport, so the
      # seeded steps run inside the new builder's loops. `name:` travels with the copy, or a
      # seeded pipeline would silently lose the anchors the four surgical edits address.
      #
      # @param pipeline [Dexpace::Pipeline, Dexpace::AsyncPipeline]
      # @return [Dexpace::Pipeline::Builder]
      def self.flattening(pipeline)
        new(transport: pipeline.transport).reload(pipeline.entries)
      end

      # PIPE-35 NEST: a new builder whose transport IS the pipeline -- legal because a pipeline
      # is a transport (PIPE-26) -- so the new builder's steps run once, OUTSIDE the nested
      # pipeline's loops. The two constructors are the explicit flatten-versus-nest choice the
      # requirement demands.
      #
      # @param pipeline [Dexpace::Pipeline, Dexpace::AsyncPipeline]
      # @return [Dexpace::Pipeline::Builder]
      def self.nesting(pipeline) = new(transport: pipeline)

      # @param transport [#call] the terminal hop, validated at #build / #build_async
      def initialize(transport:)
        @transport = transport
        @buckets = Stages::ALL.reject(&:terminal?).to_h { |stage| [stage, []] }
      end

      # PIPE-7: to the tail of the stage. `name:` is the optional surgical-edit anchor (Entry),
      # addressing exactly one entry -- what a type anchor cannot do for a lambda step, every
      # lambda's class being Proc.
      #
      # @param step [#call] a two-argument callable
      # @param stage [Dexpace::Pipeline::Stage, Symbol, String, nil] per R10's table
      # @param name [Symbol, String, nil]
      # @return [self]
      def append(step, stage: nil, name: nil)
        install(effective_stage(step, stage), step, name) { |bucket, entry| bucket << entry }
      end

      # PIPE-7: to the head of the stage.
      #
      # @return [self]
      def prepend(step, stage: nil, name: nil)
        install(effective_stage(step, stage), step, name) { |bucket, entry| bucket.unshift(entry) }
      end

      # PIPE-38: append-all preserves the batch's iteration order within each stage. A name
      # addresses exactly one entry, so naming a batch of more than one is a caller bug rather
      # than a shorthand.
      #
      # @return [self]
      def append_all(steps, stage: nil, name: nil)
        reject_batch_name!(steps, name)
        steps.each { |step| append(step, stage: stage, name: name) }
        self
      end

      # PIPE-38's asymmetry, which the requirement says a port MUST document: prepend-all prepends
      # each element INDIVIDUALLY, so `[a, b, c]` ends up `c, b, a` within the stage, while
      # append-all keeps `a, b, c`. The reversal is a consequence of the definition rather than a
      # special case, and it is stated here because a caller reading the signature alone would
      # expect the batch's order.
      #
      # @return [self]
      def prepend_all(steps, stage: nil, name: nil)
        reject_batch_name!(steps, name)
        steps.each { |step| prepend(step, stage: stage, name: name) }
        self
      end

      # PIPE-18: immediately after the FIRST step in flattened order that is an instance of
      # `anchor` -- or, for a Symbol or String, the one entry carrying that name. The step must
      # land in the anchor's stage; a cross-stage insert is rejected rather than relocated.
      #
      # The four surgical edits are keyed by step TYPE, and every lambda step has the class Proc,
      # so in a pipeline holding two lambdas `insert_after(Proc, ...)` anchors on whichever
      # flattens first and `remove(Proc)` deletes both. A step intended as an anchor should be a
      # named class, or should carry Entry's `name:` and be anchored by that name instead.
      #
      # @param anchor [Class, Module, Symbol, String]
      # @return [self]
      # @raise [Dexpace::PipelineError] for an absent anchor (PIPE-21) or a cross-stage move
      # @raise [Dexpace::InvalidArgumentError] for an anchor that is neither a type nor a name
      def insert_after(anchor, step, stage: nil, name: nil)
        surgical(anchor, step, stage, name) do |bucket, index, entry|
          bucket.insert(index + 1, entry)
        end
      end

      # PIPE-18: immediately before the first anchor instance; the same rules as #insert_after.
      #
      # @return [self]
      def insert_before(anchor, step, stage: nil, name: nil)
        surgical(anchor, step, stage, name) { |bucket, index, entry| bucket.insert(index, entry) }
      end

      # PIPE-19: swap the first anchor instance 1:1 with `step`, in the anchor's stage. Cannot
      # collide (it replaces the occupant it matched); a cross-stage replacement fails with the
      # distinct cross-stage error PIPE-5's parenthesis names -- a distinct message, one class.
      #
      # @return [self]
      def replace(anchor, step, stage: nil, name: nil)
        surgical(anchor, step, stage, name, exclusive: false) do |bucket, index, entry|
          bucket[index] = entry
        end
      end

      # PIPE-20: delete EVERY instance of the type, relative order preserved, a silent no-op when
      # absent. A name addresses exactly one entry, so a name anchor removes one.
      #
      # @return [self]
      # @raise [Dexpace::InvalidArgumentError] for an anchor that is neither a type nor a name
      def remove(anchor)
        validate_anchor!(anchor)
        @buckets.each_value { |bucket| bucket.reject! { |entry| anchor_matches?(entry, anchor) } }
        self
      end

      # PIPE-23, all-or-nothing. The whole set is validated -- every element an Entry, AND pillar
      # exclusivity over the incoming set, which is the collision the requirement's own sentence
      # is about and which PIPE-5 names the bulk path for -- BEFORE a single bucket is cleared, so
      # a rejected reload leaves the existing collection completely unchanged without a rescue or
      # a snapshot.
      #
      # @param entries [Array<Dexpace::Pipeline::Entry>]
      # @return [self]
      # @raise [Dexpace::PipelineError] on a malformed set or a pillar collision within it
      def reload(entries)
        validated = validate_bulk(entries)
        @buckets.each_value(&:clear)
        commit(validated)
      end

      # PIPE-24: empty target pillars ONLY, validated up front, the WHOLE call rejected on any
      # occupied pillar with every occupant named, never an overlay. It shares validate-then-commit
      # with #reload so "all-or-nothing" is one code path and the two requirements cannot drift --
      # which is also why a preset that collides with ITSELF on a pillar is rejected. The same
      # object already occupying a pillar is not a collision (PIPE-6) and is not re-installed.
      #
      # R14 / P4-34: this is the mechanism, and Pipeline.standard and AsyncPipeline.standard --
      # written by phase 6b's Task 13a once the redirect, retry and instrumentation families all
      # existed -- are the two step SETS written OVER it, with no second installation path.
      #
      # @param entries [Array<Dexpace::Pipeline::Entry>]
      # @return [self]
      # @raise [Dexpace::PipelineError] naming every occupied target pillar
      def install_preset(entries)
        validated = validate_bulk(entries)
        occupied = validated.filter_map { |entry| occupancy(entry) }
        unless occupied.empty?
          raise PipelineError, "cannot install preset: #{occupied.join("; ")} (PIPE-24)"
        end

        commit(validated.reject { |entry| same_occupant?(entry) })
      end

      # The flattened order as it currently stands (PIPE-22, PIPE-25): a fresh frozen Array,
      # Stages::ALL's order with SEND skipped.
      #
      # @return [Array<Dexpace::Pipeline::Entry>]
      def entries = Stages::ALL.filter_map { |stage| @buckets[stage] }.flatten(1).freeze

      # PIPE-25: flatten once into an immutable sync runtime. The transport is checked here with
      # phase 2's own predicate (plan open question 4), which catches a non-callable and a wrong
      # arity and nothing else. SyncDriver is a private_constant of Dexpace::Pipeline and
      # resolves unqualified HERE, because Builder is nested inside that class -- which is why the
      # driver travels to the runtime as a constructor argument (plan open question 9).
      #
      # @return [Dexpace::Pipeline]
      # @raise [Dexpace::InvalidArgumentError] for a transport that is not callable with three
      #   positional arguments
      def build
        validate_transport!(Dexpace::Transport, "transport")
        Pipeline.send(:new, entries: entries, transport: @transport, driver_class: SyncDriver)
      end

      # The async mirror of #build. The discriminator between a sync and an async pipeline is
      # WHICH METHOD THE CALLER CALLED, and that is documented rather than checked:
      # Transport.conforms? and AsyncTransport.conforms? are one predicate over #parameters, so
      # neither can tell the two seams apart -- they differ only in return type (P4-30's cost).
      # What the runtime does check is what comes back: an async step or transport that returns
      # something other than a Dexpace::Async::Future fails the drive with Dexpace::SeamError.
      #
      # @return [Dexpace::AsyncPipeline]
      # @raise [Dexpace::InvalidArgumentError] for a transport that is not callable with three
      #   positional arguments
      def build_async
        validate_transport!(Dexpace::AsyncTransport, "async transport")
        AsyncPipeline.send(:new, entries: entries, transport: @transport, driver_class: AsyncDriver)
      end

      private

      # R10's precedence table, all five rows, for every install and every surgical edit.
      def effective_stage(step, given)
        declared = step.respond_to?(:stage) ? resolve(step.stage) : nil
        given = resolve(given) unless given.nil?
        refuse_disagreement!(declared, given)
        stage = declared || given
        return stage unless stage.nil?

        raise PipelineError, "step does not declare #stage and no stage: keyword was given; " \
                             "a step with no stage cannot be installed (R10)"
      end

      # R10 row 3: a declaration and an argument that differ are rejected, never resolved.
      def refuse_disagreement!(declared, given)
        return if declared.nil? || given.nil? || declared.equal?(given)

        raise PipelineError, "step declares stage #{declared.name} but was installed with " \
                             "stage #{given.name} (R10)"
      end

      # Every stage the builder holds is one of the sixteen constants BY IDENTITY, so a Stage
      # argument is canonicalised through Stages.of rather than taken as given: Data#dup, #clone
      # and a Marshal round-trip each yield a copy that is == the constant and not equal? to it,
      # and the two identity comparisons below (R10 row 3 and PIPE-18's cross-stage check) would
      # otherwise refuse such a copy with a message naming the same stage on both sides.
      def resolve(stage) = Stages.of(stage.is_a?(Stage) ? stage.name : stage)

      # Entry.build carries PIPE-8's rejection; the pillar rule and the insertion are here.
      def install(stage, step, name)
        entry = Entry.build(stage: stage, step: step, name: name)
        bucket = @buckets.fetch(stage)
        return self if same_occupant_of?(stage, bucket, step) # PIPE-6: idempotent

        refuse_collision!(stage, bucket, step)
        yield bucket, entry
        self
      end

      # PIPE-6's "same", in one expression for every install path: the pillar's occupant is this
      # very object. #equal?, never == (see the class comment).
      def same_occupant_of?(stage, bucket, step)
        stage.pillar? && bucket.first&.step.equal?(step)
      end

      # PIPE-5, and PIPE-6's "no error" half is the same-object return in #install and #surgical.
      def refuse_collision!(stage, bucket, step)
        return unless stage.pillar? && !bucket.empty?

        raise PipelineError,
              "pillar #{stage.name} is already occupied by #{bucket.first.step.class}; cannot " \
              "install #{step.class} (use #replace to substitute) (PIPE-5)"
      end

      # The insert-relative edits and #replace. PIPE-5 names insert-after and insert-before among
      # the paths its distinct-step rule covers, so PIPE-6's same-object half reaches them too: an
      # exclusive insert of a pillar's own occupant beside itself -- the only entry a pillar's
      # bucket can hold, once the cross-stage check has passed -- is a no-op, as it is on #append.
      def surgical(anchor, step, stage, name, exclusive: true)
        anchor_entry, bucket = find_anchor(anchor)
        target = effective_stage(step, stage)
        unless target.equal?(anchor_entry.stage)
          raise PipelineError,
                "cannot insert #{step.class} declaring stage #{target.name} relative to anchor " \
                "at stage #{anchor_entry.stage.name} (PIPE-18)"
        end
        if exclusive
          return self if same_occupant_of?(target, bucket, step) # PIPE-6: idempotent

          refuse_collision!(target, bucket, step)
        end

        index = bucket.index(anchor_entry) or raise SeamError, "anchor vanished from its bucket"
        yield bucket, index, Entry.build(stage: target, step: step, name: name)
        self
      end

      # The first entry in flattened order matching `anchor`, and its bucket; PIPE-21's error
      # identifying the missing type -- or the missing name, for the same reason -- otherwise.
      def find_anchor(anchor)
        validate_anchor!(anchor)
        match = entries.find { |entry| anchor_matches?(entry, anchor) }
        if match.nil?
          raise PipelineError, "#{describe_anchor(anchor)} was not found in pipeline (PIPE-21)"
        end

        [match, @buckets.fetch(match.stage)]
      end

      # A Symbol or String anchors on Entry#name; anything else is a type anchor, unchanged.
      def anchor_matches?(entry, anchor)
        return entry.step.is_a?(anchor) unless named?(anchor)

        !entry.name.nil? && entry.name.to_s == anchor.to_s
      end

      def named?(anchor) = anchor.is_a?(::Symbol) || anchor.is_a?(::String)

      # Checked once, up front, so a mistyped anchor fails in the SDK's own form rather than as
      # Ruby's `TypeError: class or module required` out of #is_a? -- which an unchecked anchor
      # would raise only once an entry existed to compare against, and never on an empty builder.
      def validate_anchor!(anchor)
        return if anchor.is_a?(::Module) || named?(anchor)

        raise InvalidArgumentError, "anchor takes a Module, Symbol or String, got #{anchor.class}"
      end

      def describe_anchor(anchor)
        named?(anchor) ? "anchor step named #{anchor.inspect}" : "anchor step of type #{anchor}"
      end

      def reject_batch_name!(steps, name)
        return if name.nil? || steps.size <= 1

        raise PipelineError,
              "name: #{name.inspect} addresses exactly one entry and cannot be given for a " \
              "batch of #{steps.size} steps (PIPE-18)"
      end

      # PIPE-23/PIPE-24's shared validate half: every element an Entry, then PIPE-4's at-most-one
      # rule over the INCOMING set with PIPE-6's idempotence in the same pass. Distinctness is
      # #equal?, never ==. Two DISTINCT steps on one pillar reject the whole call; the SAME step
      # twice collapses to one entry.
      def validate_bulk(entries)
        unless entries.is_a?(::Array) && entries.all?(Entry)
          raise PipelineError, "cannot reload pipeline entries: expected an Array of " \
                               "Dexpace::Pipeline::Entry (PIPE-23)"
        end

        seen = {} #: Hash[Stage, untyped]
        entries.reject { |entry| entry.stage.pillar? && repeated_occupant?(seen, entry) }
      end

      # Over one incoming set: false for a pillar's first claimant (recorded), true for the SAME
      # step claiming it again (collapsed, PIPE-6), a raise for a DISTINCT second step.
      def repeated_occupant?(seen, entry)
        occupant = seen[entry.stage]
        if occupant.nil?
          seen[entry.stage] = entry.step
          return false
        end
        return true if occupant.equal?(entry.step)

        raise PipelineError,
              "pillar #{entry.stage.name} would hold 2 distinct steps (#{occupant.class}, " \
              "#{entry.step.class}); a pillar admits at most one (PIPE-4, PIPE-5; rejected " \
              "whole per PIPE-23 and PIPE-24)"
      end

      def commit(validated)
        validated.each { |entry| @buckets.fetch(entry.stage) << entry }
        self
      end

      # PIPE-24's clause, one phrase per occupied target pillar; nil for an empty one or one the
      # same object already occupies.
      def occupancy(entry)
        return nil unless entry.stage.pillar? && !same_occupant?(entry)

        existing = @buckets.fetch(entry.stage).first or return nil
        "pillar #{entry.stage.name} is already occupied by #{existing.step.class}"
      end

      def same_occupant?(entry)
        same_occupant_of?(entry.stage, @buckets.fetch(entry.stage), entry.step)
      end

      # Plan open question 4: phase 2's own predicate, not a local respond_to?(:call). Both seams
      # reduce to Dexpace::Registry.callable?(object, arity: 3), so there is one shape predicate.
      def validate_transport!(seam, label)
        return if seam.conforms?(@transport)

        raise InvalidArgumentError,
              "a #{label} responds to #call(request, options, cancellation); " \
              "#{@transport.class} does not"
      end
    end
  end
end
