# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/probe_step"

# PIPE-4, PIPE-5, PIPE-6, PIPE-7, PIPE-8, PIPE-18, PIPE-19, PIPE-20, PIPE-21, PIPE-22, PIPE-23,
# PIPE-24, PIPE-38, and R10's five-row precedence table. PIPE-25 and PIPE-35 are asserted through
# a built runtime and live in pipeline_test.rb.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# installs and the pillar rules here, the surgical edits, R10, and the two bulk paths below.
class DexpacePipelineBuilderTest < DexpaceTestCase
  STAGES = Dexpace::Pipeline::Stages

  # Shared by every class below.
  module Builders
    def setup
      super
      @transport = ->(_req, _opts, _canc) { "ok" }
      @builder = Dexpace::Pipeline::Builder.new(transport: @transport)
    end

    def probe(tag, log = []) = ProbeStep.new(tag: tag, log: log)
    def lambda_step = ->(req, cur) { cur.call(req) }
    def entry(stage, step) = Dexpace::Pipeline::Entry.build(stage: stage, step: step)
    def steps_of(builder) = builder.entries.map(&:step)
  end
  include Builders

  # SEAM-29's contract, reached as Dexpace::Builder from inside class Pipeline, where a bare
  # Builder is this one; Dexpace::Builder.build_all over it is asserted in pipeline_test.rb.
  test "a builder is phase 1's builder contract, and every install returns self for chaining" do
    assert_kind_of(Dexpace::Builder, @builder)
    assert_same(@builder, @builder.append(probe(:a), stage: STAGES::PRE_AUTH))
    assert_same(@builder, @builder.prepend(probe(:b), stage: STAGES::PRE_AUTH))
    assert_same(@builder, @builder.append_all([probe(:c)], stage: STAGES::PRE_AUTH))
    assert_same(@builder, @builder.prepend_all([probe(:d)], stage: STAGES::PRE_AUTH))
    assert_same(@builder, @builder.remove(ProbeStep))
  end

  # PIPE-5 and PIPE-6 are two halves of one rule, and the fixture is what makes the second half
  # real: two Data probes over ONE shared log are == and not equal?, so an ==-based collision check
  # would swallow the collision (verified fact 3, the CTX-9 trap).
  test "PIPE-5 & PIPE-6: pillar exclusivity is by identity, and the same object is idempotent" do
    log = []
    first = probe(:retry, log)
    second = probe(:retry, log)

    assert_equal(first, second, "value-equal")
    refute_same(first, second, "distinct objects")

    @builder.append(first, stage: STAGES::RETRY)
    @builder.append(first, stage: STAGES::RETRY)

    assert_equal(1, @builder.entries.size, "re-installing the same object is a no-op (PIPE-6)")

    error = assert_raises(Dexpace::PipelineError) { @builder.append(second, stage: STAGES::RETRY) }

    assert_includes(
      error.message,
      "pillar retry is already occupied by ProbeStep; cannot install ProbeStep " \
      "(use #replace to substitute) (PIPE-5)",
    )
    assert_equal(1, @builder.entries.size, "a rejected install changes nothing")
  end

  test "PIPE-5: prepend onto an occupied pillar collides the same way" do
    @builder.append(probe(:a), stage: STAGES::AUTH)

    assert_raises(Dexpace::PipelineError) { @builder.prepend(probe(:b), stage: STAGES::AUTH) }
    assert_equal(1, @builder.entries.size)
  end

  test "PIPE-8: a step cannot be installed at the terminal SEND stage, by Stage or by name" do
    error = assert_raises(Dexpace::PipelineError) do
      @builder.append(lambda_step, stage: STAGES::SEND)
    end

    assert_includes(error.message, "cannot install step at terminal stage SEND (PIPE-8)")
    assert_raises(Dexpace::PipelineError) { @builder.append(lambda_step, stage: :send) }
    assert_empty(@builder.entries)
  end

  test "PIPE-7: append adds to the tail and prepend to the head within a non-pillar stage" do
    a = probe(:a)
    b = probe(:b)
    c = probe(:c)

    @builder.append(a, stage: STAGES::PRE_AUTH)
    @builder.append(b, stage: STAGES::PRE_AUTH)
    @builder.prepend(c, stage: STAGES::PRE_AUTH)

    assert_equal([c, a, b], steps_of(@builder))
  end

  # PIPE-1's flattening is derived from the stage table, never from insertion order: a step in a
  # lower-ordered stage runs before one in a higher-ordered stage whatever order they were added
  # in, and SEND holds nothing to flatten.
  test "PIPE-7 & PIPE-22: flattening derives from the stage table, not from insertion order" do
    late = probe(:late)
    early = probe(:early)
    middle = probe(:middle)

    @builder.append(late, stage: STAGES::POST_SERDE)
    @builder.append(middle, stage: :auth)
    @builder.append(early, stage: STAGES::PRE_REDIRECT)

    assert_equal([early, middle, late], steps_of(@builder))
    assert_equal(%i[pre_redirect auth post_serde], @builder.entries.map { |e| e.stage.name })
  end

  test "#entries is a frozen snapshot that later installs do not reach" do
    @builder.append(probe(:a), stage: STAGES::PRE_AUTH)
    snapshot = @builder.entries
    @builder.append(probe(:b), stage: STAGES::PRE_AUTH)

    assert_predicate(snapshot, :frozen?)
    assert_equal(1, snapshot.size)
    assert_equal(2, @builder.entries.size)
  end

  # PIPE-18 to PIPE-21: the four surgical edits, by type and by name.
  class SurgicalTest < DexpaceTestCase
    include Builders

    test "PIPE-18: insert_after and insert_before place next to the FIRST anchor instance" do
      a = probe(:a)
      b = probe(:b)
      after = lambda_step
      before = lambda_step
      @builder.append_all([a, b], stage: STAGES::PRE_AUTH)

      @builder.insert_after(ProbeStep, after, stage: STAGES::PRE_AUTH)
      @builder.insert_before(ProbeStep, before, stage: STAGES::PRE_AUTH)

      assert_equal([before, a, after, b], steps_of(@builder))
    end

    test "PIPE-18: a cross-stage insert is rejected naming both stages, and installs nothing" do
      @builder.append(probe(:anchor), stage: STAGES::PRE_AUTH)

      error = assert_raises(Dexpace::PipelineError) do
        @builder.insert_after(ProbeStep, lambda_step, stage: STAGES::POST_AUTH)
      end

      assert_includes(
        error.message,
        "cannot insert Proc declaring stage post_auth relative to anchor at stage pre_auth " \
        "(PIPE-18)",
      )
      assert_equal(1, @builder.entries.size)
    end

    test "PIPE-18 & PIPE-5: a surgical insert onto an occupied pillar collides like an append" do
      occupant = probe(:occupant)
      @builder.append(occupant, stage: STAGES::RETRY)

      error = assert_raises(Dexpace::PipelineError) do
        @builder.insert_after(ProbeStep, probe(:second), stage: STAGES::RETRY)
      end

      assert_includes(error.message, "(PIPE-5)")
      assert_equal([occupant], steps_of(@builder))
    end

    test "PIPE-19: replace swaps the first anchor instance 1:1 at the same stage" do
      old = probe(:old)
      other = probe(:other)
      fresh = probe(:new)
      @builder.append_all([old, other], stage: STAGES::PRE_AUTH)

      @builder.replace(ProbeStep, fresh, stage: STAGES::PRE_AUTH)

      assert_equal([fresh, other], steps_of(@builder))
    end

    test "PIPE-19: replace on a pillar substitutes its one occupant without a collision" do
      old = probe(:old)
      fresh = probe(:new)
      @builder.append(old, stage: STAGES::RETRY)

      @builder.replace(ProbeStep, fresh, stage: STAGES::RETRY)

      assert_equal([fresh], steps_of(@builder))
    end

    test "PIPE-19: a cross-stage replace is rejected with the cross-stage error, not PIPE-5's" do
      @builder.append(probe(:old), stage: STAGES::PRE_AUTH)

      error = assert_raises(Dexpace::PipelineError) do
        @builder.replace(ProbeStep, probe(:new), stage: STAGES::AUTH)
      end

      assert_includes(error.message, "(PIPE-18)")
      refute_includes(error.message, "PIPE-5")
    end

    test "PIPE-20: remove deletes every instance of the type, keeps order, no-ops when absent" do
      first = probe(:s1)
      middle = lambda_step
      last = probe(:s2)
      @builder.append(first, stage: STAGES::PRE_AUTH)
      @builder.append(middle, stage: STAGES::PRE_AUTH)
      @builder.append(last, stage: STAGES::POST_AUTH)

      assert_same(@builder, @builder.remove(String), "absent: a silent no-op")
      assert_equal(3, @builder.entries.size)

      @builder.remove(ProbeStep)

      assert_equal([middle], steps_of(@builder))
    end

    test "PIPE-21: an insert or replace whose anchor type is absent fails identifying the type" do
      error = assert_raises(Dexpace::PipelineError) do
        @builder.insert_after(String, probe(:s1), stage: STAGES::PRE_AUTH)
      end

      assert_includes(error.message,
                      "anchor step of type String was not found in pipeline (PIPE-21)",)
      assert_raises(Dexpace::PipelineError) { @builder.replace(String, probe(:s1), stage: :pre_auth) }
      assert_empty(@builder.entries)
    end
  end

  # The 2026-09-13 amendment: the optional anchor name, by which the four edits reach a lambda.
  class NameAnchorTest < DexpaceTestCase
    include Builders

    # The 2026-09-13 amendment, and the case that makes PIPE-18-PIPE-21 reach a lambda step at
    # all. Both lambdas below have the class Proc (verified fact 13), so insert_after(Proc, ...)
    # anchors arbitrarily; the name addresses exactly one of them. Type anchoring is unchanged.
    test "PIPE-18 / PIPE-20: a name anchors one lambda where a type anchors all of them" do
      first = lambda_step
      second = lambda_step
      inserted = lambda_step
      pre_auth = STAGES::PRE_AUTH

      assert_instance_of(Proc, first)
      assert_equal(first.class, second.class, "a type anchor cannot tell two lambdas apart")

      @builder.append(first, stage: pre_auth, name: :first_hook)
      @builder.append(second, stage: pre_auth, name: "second_hook")
      @builder.insert_after(:second_hook, inserted, stage: pre_auth, name: :inserted_hook)

      assert_equal([first, second, inserted], steps_of(@builder))
      assert_equal([:first_hook, "second_hook", :inserted_hook], @builder.entries.map(&:name))

      # PIPE-20 keeps its type semantics; a name removes the one entry it names, by either
      # spelling.
      @builder.remove("second_hook")

      assert_equal([first, inserted], steps_of(@builder))

      @builder.remove(Proc)

      assert_empty(@builder.entries)
    end

    test "PIPE-21: an absent name anchor fails identifying the name rather than no-op'ing" do
      @builder.append(lambda_step, stage: STAGES::PRE_AUTH, name: :present)

      error = assert_raises(Dexpace::PipelineError) do
        @builder.replace(:absent, lambda_step, stage: STAGES::PRE_AUTH)
      end

      assert_includes(error.message,
                      "anchor step named :absent was not found in pipeline (PIPE-21)",)
      assert_equal(1, @builder.entries.size, "a failed edit changes nothing")
    end

    test "a name addresses one entry, so a batch of more than one cannot carry one" do
      error = assert_raises(Dexpace::PipelineError) do
        @builder.append_all([lambda_step, lambda_step], stage: STAGES::POST_AUTH, name: :batch)
      end

      assert_includes(error.message, "addresses exactly one entry")
      assert_empty(@builder.entries)
      @builder.prepend_all([lambda_step], stage: STAGES::POST_AUTH, name: :single)

      assert_equal([:single], @builder.entries.map(&:name))
    end
  end

  # R10's precedence table, all five rows, and PIPE-38.
  class StageAssignmentTest < DexpaceTestCase
    include Builders

    def declaring_class
      Class.new do
        def stage = Dexpace::Pipeline::Stages::RETRY
        def call(req, cur) = cur.call(req)
      end
    end

    # Rows 3 and 4 are the two rejections; a test that only covered the accepting rows would pass
    # against an implementation that silently resolved a disagreement in either direction, which
    # is what R10 exists to forbid.
    test "R10 rows 1, 2 and 5: a declared stage, an agreeing argument, or the argument alone" do
      declaring = declaring_class

      assert_same(STAGES::RETRY, @builder.append(declaring.new).entries[0].stage)

      b2 = Dexpace::Pipeline::Builder.new(transport: @transport)

      assert_same(STAGES::RETRY, b2.append(declaring.new, stage: STAGES::RETRY).entries[0].stage)

      b5 = Dexpace::Pipeline::Builder.new(transport: @transport)

      assert_same(STAGES::PRE_AUTH, b5.append(lambda_step, stage: :pre_auth).entries[0].stage)
    end

    test "R10 row 3: a declared stage and a DIFFERENT argument is rejected, naming both" do
      error = assert_raises(Dexpace::PipelineError) do
        @builder.append(declaring_class.new, stage: STAGES::AUTH)
      end

      assert_includes(error.message,
                      "step declares stage retry but was installed with stage auth (R10)",)
      assert_empty(@builder.entries)
    end

    # A lambda cannot respond to #stage (verified fact 6), so this is the row every hand-written
    # step meets first.
    test "R10 row 4: a step that declares nothing and is given nothing is rejected" do
      error = assert_raises(Dexpace::PipelineError) { @builder.append(lambda_step) }

      assert_includes(error.message, "a step with no stage cannot be installed (R10)")
    end

    test "R10: a declared stage may be a Symbol name, and a declared SEND is rejected too" do
      by_name = Class.new do
        def stage = :post_auth
        def call(req, cur) = cur.call(req)
      end
      at_send = Class.new do
        def stage = :send
        def call(req, cur) = cur.call(req)
      end

      assert_same(STAGES::POST_AUTH, @builder.append(by_name.new).entries[0].stage)
      assert_raises(Dexpace::PipelineError) { @builder.append(at_send.new) }
    end

    # R10 again, on the surgical side: stage: is required rather than inferred from the anchor,
    # because inferring it would make PIPE-18's own cross-stage rejection unreachable for a lambda.
    test "PIPE-18 / R10: a surgical edit never infers the anchor's stage for a lambda" do
      @builder.append(probe(:anchor), stage: STAGES::PRE_AUTH)

      error = assert_raises(Dexpace::PipelineError) do
        @builder.insert_after(ProbeStep, lambda_step)
      end

      assert_includes(error.message, "a step with no stage cannot be installed (R10)")
      assert_equal(1, @builder.entries.size)
    end

    test "PIPE-18 / R10: a declaring step inserted beside another stage's anchor is rejected" do
      @builder.append(probe(:anchor), stage: STAGES::PRE_AUTH)

      error = assert_raises(Dexpace::PipelineError) do
        @builder.insert_before(ProbeStep, declaring_class.new)
      end

      assert_includes(error.message, "declaring stage retry relative to anchor at stage pre_auth")
    end

    test "PIPE-38: append_all preserves the batch's order; prepend_all reverses it" do
      s1 = probe(:s1)
      s2 = probe(:s2)
      s3 = probe(:s3)

      b_append = Dexpace::Pipeline::Builder.new(transport: @transport)
      b_append.append_all([s1, s2, s3], stage: STAGES::PRE_AUTH)

      assert_equal([s1, s2, s3], steps_of(b_append))

      b_prepend = Dexpace::Pipeline::Builder.new(transport: @transport)
      b_prepend.prepend_all([s1, s2, s3], stage: STAGES::PRE_AUTH)

      assert_equal([s3, s2, s1], steps_of(b_prepend))
    end
  end

  # PIPE-22's determinism and the two all-or-nothing bulk paths, PIPE-23 and PIPE-24.
  class BulkTest < DexpaceTestCase
    include Builders

    test "PIPE-22: an edited builder's entries equal a builder seeded from scratch" do
      s1 = probe(:s1)
      s2 = probe(:s2)
      s3 = probe(:s3)
      s4 = probe(:s4)
      doomed = lambda_step
      pre_auth = STAGES::PRE_AUTH

      # All three re-bucketing edits PIPE-22 names, then the same resulting step set from scratch.
      edited = Dexpace::Pipeline::Builder.new(transport: @transport)
      edited.append_all([s1, s2], stage: pre_auth)
      edited.append(doomed, stage: STAGES::POST_AUTH)
      edited.insert_after(ProbeStep, s3, stage: pre_auth)
      edited.remove(Proc)
      edited.replace(ProbeStep, s4, stage: pre_auth)

      fresh = Dexpace::Pipeline::Builder.new(transport: @transport)
      fresh.append_all([s4, s3, s2], stage: pre_auth)

      # The flattened ENTRIES, not the response: the assertion is about ordering.
      assert_equal(fresh.entries, edited.entries)
    end

    test "PIPE-23: reload replaces the whole collection and preserves within-stage order" do
      @builder.append(probe(:old), stage: STAGES::PRE_AUTH)
      a = probe(:a)
      b = probe(:b)
      c = probe(:c)

      @builder.reload([entry(STAGES::POST_AUTH, a), entry(STAGES::PRE_AUTH, b),
                       entry(STAGES::POST_AUTH, c),])

      assert_equal([b, a, c], steps_of(@builder))
    end

    test "PIPE-23: a reload with a malformed entry is rejected whole; the argument is checked" do
      @builder.append(probe(:orig), stage: STAGES::PRE_AUTH)
      snapshot = @builder.entries

      error = assert_raises(Dexpace::PipelineError) do
        @builder.reload([entry(STAGES::POST_AUTH, probe(:a)), Object.new])
      end

      assert_includes(error.message, "cannot reload pipeline entries")
      assert_equal(snapshot, @builder.entries, "the existing collection is completely unchanged")
      assert_raises(Dexpace::PipelineError) { @builder.reload(nil) }
    end

    # PIPE-23's all-or-nothing clause is written ABOUT this case -- "if it encounters a pillar
    # collision (a distinct second step for an occupied pillar), it MUST leave the existing
    # collection completely unchanged" -- and PIPE-5 names the bulk path outright. A reload that
    # only type-checks its entries installs two steps on a pillar and violates PIPE-4 silently,
    # which the malformed-entry test above would never see.
    test "PIPE-23 & PIPE-5: reload rejects a pillar collision in the set and installs nothing" do
      @builder.append(probe(:orig), stage: STAGES::PRE_AUTH)
      snapshot = @builder.entries
      log = []
      first = probe(:r, log)
      second = probe(:r, log)

      assert_equal(first, second, "value-equal, so an ==-based check would miss the collision")
      refute_same(first, second)

      colliding = [entry(STAGES::RETRY, first), entry(STAGES::RETRY, second)]
      error = assert_raises(Dexpace::PipelineError) { @builder.reload(colliding) }

      assert_includes(error.message, "pillar retry would hold 2 distinct steps")
      assert_equal(snapshot, @builder.entries)

      # PIPE-6's identity rule from the other side: the SAME object twice is not a collision, and
      # it collapses to one entry rather than duplicating ("no error, no duplication").
      @builder.reload([colliding.first, entry(STAGES::RETRY, first)])

      assert_equal([first], steps_of(@builder))
    end

    test "PIPE-24: install_preset rejects the whole call naming every occupied pillar" do
      existing = probe(:existing)
      @builder.append(existing, stage: STAGES::RETRY)
      @builder.append(lambda_step, stage: STAGES::AUTH)
      snapshot = @builder.entries
      preset = [entry(STAGES::REDIRECT, probe(:p1)), entry(STAGES::RETRY, probe(:p2)),
                entry(STAGES::AUTH, probe(:p3)),]

      error = assert_raises(Dexpace::PipelineError) { @builder.install_preset(preset) }

      assert_includes(
        error.message,
        "cannot install preset: pillar retry is already occupied by ProbeStep; " \
        "pillar auth is already occupied by Proc (PIPE-24)",
      )
      assert_equal(snapshot, @builder.entries, "installing nothing")
      assert_empty(@builder.entries.select { |e| e.stage.equal?(STAGES::REDIRECT) })
    end

    test "PIPE-24: install_preset fills empty pillars, and the same occupant is not a collision" do
      redirect = probe(:redirect)
      retry_step = probe(:retry)
      @builder.append(retry_step, stage: STAGES::RETRY)

      @builder.install_preset([entry(STAGES::REDIRECT, redirect),
                               entry(STAGES::RETRY, retry_step),])

      assert_equal([redirect, retry_step], steps_of(@builder))
    end

    # The other half of PIPE-24's "installing nothing": a preset whose OWN entries collide on a
    # pillar. The occupancy check passes (the target pillars are empty), so without the shared
    # validate-then-commit check a preset would install two steps on one pillar -- PIPE-4
    # violated by the very method PIPE-24 exists to constrain.
    test "PIPE-24 & PIPE-4: a preset colliding with itself on a pillar installs nothing" do
      @builder.append(probe(:slot), stage: STAGES::PRE_AUTH)
      snapshot = @builder.entries
      log = []
      preset = [entry(STAGES::REDIRECT, probe(:a, log)), entry(STAGES::REDIRECT, probe(:a, log))]

      error = assert_raises(Dexpace::PipelineError) { @builder.install_preset(preset) }

      assert_includes(error.message, "pillar redirect would hold 2 distinct steps")
      assert_equal(snapshot, @builder.entries)
    end
  end
end
