# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# The suppressed-exception trail phase 1 postponed to phase 4; RECOV-12 (the close error that must
# not mask the primary), RETRY-34 (the skip-self guard). P4-12: the trail lives on a separate
# module Dexpace::Error includes, because every primary the helper is handed is a caller's
# exception and `rescue M` matches a module reached through a singleton class -- so extending a
# third-party IOError with the rescue root would widen `rescue Dexpace::Error`. P4-13, P4-14,
# P4-15 are each asserted below.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# trail and the module here, then Attach and Rendering below.
class DexpaceSuppressibleTest < DexpaceTestCase
  test "an error with no trail reads a frozen empty array" do
    error = ::StandardError.new("boom")

    assert_equal([], Dexpace.suppressed(error))
    assert_predicate(Dexpace.suppressed(error), :frozen?)
  end

  test "Dexpace::Error includes Dexpace::Suppressible, so every SDK error carries the trail" do
    assert_operator(Dexpace::Error, :<, Dexpace::Suppressible)

    error = Dexpace::SeamError.new("no provider")

    assert_kind_of(Dexpace::Suppressible, error)
    assert_equal([], error.suppressed)
    Dexpace.attach_suppressed(error, ::IOError.new("cleanup"))

    assert_equal(1, error.suppressed.size)
    assert_kind_of(Dexpace::Error, error)
  end

  test "the module declares exactly two public instance methods" do
    assert_equal(%i[detailed_message suppressed],
                 Dexpace::Suppressible.public_instance_methods(false).sort,)
  end

  # A frozen SDK error is already Suppressible by inclusion, so #suppressed is reachable on it
  # and the READER must not be the thing that raises: P4-13's no-op covers the write, and a
  # reader that memoised into an ivar would turn every read of a frozen error's trail into a
  # FrozenError.
  test "a frozen Dexpace::Error reads an empty trail and silently refuses the attach" do
    primary = Dexpace::SeamError.new("no provider").freeze

    assert_equal([], primary.suppressed)
    assert_equal([], Dexpace.suppressed(primary))
    assert_same(primary, Dexpace.attach_suppressed(primary, ::IOError.new("cleanup")))
    assert_equal([], Dexpace.suppressed(primary))
  end

  # Dexpace.attach_suppressed: the only writer, its four rules, and what it does to the object.
  class AttachTest < DexpaceTestCase
    test "extends the primary with Suppressible and not with Dexpace::Error" do
      primary = ::IOError.new("primary failure")
      secondary = ::RuntimeError.new("cleanup failure")

      result = Dexpace.attach_suppressed(primary, secondary)

      assert_same(primary, result)
      assert_kind_of(Dexpace::Suppressible, primary)
      refute_kind_of(Dexpace::Error, primary)
      trail = primary.suppressed

      assert_equal([secondary], trail)
      assert_same(secondary, trail.first)
      assert_predicate(trail, :frozen?)
      assert_raises(::FrozenError) { trail << ::StandardError.new }
    end

    # Verified fact 2: the extension is visible to `rescue`, which is the reason the extended
    # module is the trail and not the rescue root (P4-12, P4-15).
    test "rescue Dexpace::Suppressible catches an extended third-party error" do
      primary = ::IOError.new("io err")
      Dexpace.attach_suppressed(primary, ::RuntimeError.new("secondary"))

      caught = begin
        raise primary
      rescue Dexpace::Suppressible => error
        error
      end

      assert_same(primary, caught)
    end

    test "rescue Dexpace::Error still does not catch an extended third-party error" do
      primary = ::IOError.new("io err")
      Dexpace.attach_suppressed(primary, ::RuntimeError.new("secondary"))

      caught = begin
        begin
          raise primary
        rescue Dexpace::Error
          flunk("attach_suppressed must not widen rescue Dexpace::Error (P4-12)")
        end
      rescue ::IOError => error
        error
      end

      assert_same(primary, caught)
    end

    # P4-14: a frozen array replaced on every attach, never one array frozen later, so a handle
    # taken earlier stays a stable snapshot of that moment.
    test "each attach replaces the frozen trail and an earlier handle is a stable snapshot" do
      primary = ::StandardError.new("p")
      first = ::StandardError.new("s1")
      second = ::StandardError.new("s2")

      Dexpace.attach_suppressed(primary, first)
      snapshot = primary.suppressed
      Dexpace.attach_suppressed(primary, second)

      assert_equal([first], snapshot)
      assert_predicate(snapshot, :frozen?)
      assert_equal([first, second], primary.suppressed)
      assert_equal([first, second], Dexpace.suppressed(primary))
      assert_predicate(primary.suppressed, :frozen?)
    end

    # RETRY-34's guard, by identity: two structurally identical errors are == (verified fact 6),
    # so a == guard would drop a DIFFERENT error that happened to carry the same message.
    test "skips self by identity and not by equality" do
      primary = ::StandardError.new("same")
      twin = ::StandardError.new("same")

      Dexpace.attach_suppressed(primary, primary)

      assert_equal([], Dexpace.suppressed(primary))
      assert_equal(primary, twin, "the fixture must be ==, or the guard is not discriminated")

      Dexpace.attach_suppressed(primary, twin)

      assert_equal(1, Dexpace.suppressed(primary).size)
      assert_same(twin, Dexpace.suppressed(primary).first)
    end

    # P4-13: extend and the ivar write both raise FrozenError on a frozen exception (verified
    # fact 3), and a helper that raised while attaching a CLOSE error would mask the primary,
    # which is the one failure RECOV-12 exists to prevent. So the attach is a documented no-op.
    test "silently refuses a frozen third-party primary" do
      primary = ::StandardError.new("frozen").freeze
      secondary = ::StandardError.new("secondary")

      assert_same(primary, Dexpace.attach_suppressed(primary, secondary))
      assert_equal([], Dexpace.suppressed(primary))
      refute_kind_of(Dexpace::Suppressible, primary)
    end

    test "refuses a primary or a secondary that is not an Exception" do
      error = ::StandardError.new

      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace.attach_suppressed("not an error", error)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace.attach_suppressed(error, :not_an_error)
      end
      assert_equal([], Dexpace.suppressed(error))
    end
  end

  # #detailed_message: R5's exact rendering, and the two paths it reaches.
  class RenderingTest < DexpaceTestCase
    test "detailed_message is super alone when the trail is empty" do
      error = ::StandardError.new("plain")

      assert_equal(error.detailed_message, Dexpace.attach_suppressed(error, error).detailed_message)
      assert_equal("plain (StandardError)", error.detailed_message)
    end

    test "detailed_message renders the primary and one line per suppressed error, in order" do
      primary = ::StandardError.new("main failed")
      Dexpace.attach_suppressed(primary, ::IOError.new("disk error"))
      Dexpace.attach_suppressed(primary, ::ArgumentError.new("invalid val"))

      rendered = primary.detailed_message

      expected = [
        "main failed (StandardError)",
        "Suppressed exceptions (2):",
        "  (1) IOError: disk error",
        "  (2) ArgumentError: invalid val",
      ].join("\n")

      assert_equal(expected, rendered)
    end

    # Verified fact 1: Ruby's own Exception#full_message calls #detailed_message, so overriding
    # the latter alone reaches both the explicit-call path and the default uncaught-exception
    # printer; #full_message is deliberately not overridden (R5). The keywords Ruby passes reach
    # `super` unnamed: `highlight: true` still colours the header the way Ruby's own does.
    test "full_message and a highlighted detailed_message both carry the trail" do
      primary = ::StandardError.new("main failed")
      Dexpace.attach_suppressed(primary, ::IOError.new("disk error"))

      plain = primary.full_message(highlight: false, order: :top)

      assert_includes(plain, "main failed (StandardError)")
      assert_includes(plain, "  (1) IOError: disk error")

      highlighted = primary.detailed_message(highlight: true)

      assert_includes(highlighted, "\e[1m")
      assert_includes(highlighted, "  (1) IOError: disk error")
      refute_includes(Dexpace::Suppressible.instance_methods(false), :full_message)
    end

    # Verified fact 4: `super` is mandatory rather than decorative -- a NoMethodError's
    # did_you_mean suggestion survives the extension and the trail is appended after it.
    test "detailed_message keeps what Ruby's own composed before it" do
      primary = begin
        "".uppcase
      rescue ::NoMethodError => error
        error
      end
      Dexpace.attach_suppressed(primary, ::IOError.new("after"))

      rendered = primary.detailed_message(highlight: false)

      assert_includes(rendered, "uppcase")
      assert_includes(rendered, "Did you mean?")
      assert_includes(rendered, "  (1) IOError: after")
      assert_operator(rendered.index("Did you mean?"), :<, rendered.index("(1) IOError"))
    end
  end
end
