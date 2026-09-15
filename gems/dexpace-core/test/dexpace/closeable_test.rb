# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# SEAM-14, SEAM-25, XCUT-13, XCUT-22. The latch is a boolean flipped under a Thread::Mutex held
# only across the flip: Ruby's Mutex is per-fiber-owned and non-reentrant (verified on 3.2.11,
# 3.4.10 and 4.0.6), so holding it across a #release that may suspend deadlocks two fibers of one
# thread.
class DexpaceCloseableTest < DexpaceTestCase
  # An owning-or-borrowing resource that counts its releases.
  class Spy
    include Dexpace::Closeable

    attr_reader :releases

    def initialize(owned: true)
      @releases = 0
      initialize_closeable(owned: owned)
    end

    private

    def release
      @releases += 1
    end
  end

  # A resource whose release fails, for the propagate-once rule.
  class Raising
    include Dexpace::Closeable

    def initialize
      initialize_closeable(owned: true)
    end

    private

    def release
      raise ::IOError, "the socket is already gone"
    end
  end

  # An includer that never called #initialize_closeable.
  class Forgetful
    include Dexpace::Closeable
  end

  # An owning includer that never defined #release.
  class NoRelease
    include Dexpace::Closeable

    def initialize
      initialize_closeable(owned: true)
    end
  end

  test "close releases exactly once under contention" do
    spy = Spy.new

    Array.new(16) { ::Thread.new { spy.close } }.each(&:join)

    assert_equal(1, spy.releases)
    assert_predicate_by_respond_to(spy, :closed?)
  end

  test "a borrowed resource latches but is never released" do
    spy = Spy.new(owned: false)

    spy.close

    assert_equal(0, spy.releases)
    refute_predicate(spy, :owned?)
    assert_predicate(spy, :closed?, "XCUT-22: the component is closed, the resource is not")
  end

  test "an owned resource reports so, and is released by the first close only" do
    spy = Spy.new

    assert_predicate(spy, :owned?)
    refute_predicate(spy, :closed?)
    assert_nil(spy.close)
    assert_nil(spy.close)
    assert_equal(1, spy.releases, "SEAM-25: only the first close releases")
  end

  test "a release that raises still leaves the latch flipped and propagates once" do
    raising = Raising.new

    assert_raises(::IOError) { raising.close }

    assert_predicate(raising, :closed?)
    assert_nil(raising.close, "BODY-27: no second release is attempted")
  end

  test "an including class that never initialised the latch fails loudly" do
    error = assert_raises(Dexpace::SeamError) { Forgetful.new.close }

    assert_match(/initialize_closeable/, error.message)
    assert_raises(Dexpace::SeamError) { Forgetful.new.closed? }
    assert_raises(Dexpace::SeamError) { Forgetful.new.owned? }
  end

  # NotImplementedError is a ScriptError, not a StandardError: a class that forgot #release is a
  # programmer error and must not be swallowed by an ordinary rescue -- the same reasoning as
  # phase 1's Dexpace::Builder#build.
  test "an owning class that never defined release fails as a programmer error" do
    error = assert_raises(::NotImplementedError) { NoRelease.new.close }

    assert_match(/release/, error.message)
  end

  test "close_quietly is null-safe and tolerates a resource with no close" do
    assert_nil(Dexpace.close_quietly(nil))
    assert_nil(Dexpace.close_quietly(Object.new))
  end

  test "close_quietly closes what it is given and swallows a close failure" do
    spy = Spy.new

    Dexpace.close_quietly(spy)

    assert_equal(1, spy.releases)
    # The rescued error is dropped until phase 4b (Task 2) supplies the suppressed trail and phase
    # 5b (Task 14) the instrumentation diagnostic. Asserted rather than left as a comment, so the
    # day a route lands this test is what has to change.
    assert_nil(Dexpace.close_quietly(Raising.new))
  end

  # A NotImplementedError or any other non-StandardError is not a close failure to be swallowed.
  test "close_quietly does not swallow a programmer error from close" do
    assert_raises(::NotImplementedError) { Dexpace.close_quietly(NoRelease.new) }
  end

  # Minitest sends past `private`, verified on 5.25.1/3.2.11 and 6.0.0/4.0.6, so visibility is
  # asserted with respond_to? and never with assert_predicate (phase 1's finding).
  test "release is private and the latch queries are public" do
    spy = Spy.new

    refute_respond_to(spy, :release)
    assert_respond_to(spy, :close)
    assert_respond_to(spy, :closed?)
    assert_respond_to(spy, :owned?)
  end

  private

  def assert_predicate_by_respond_to(object, name)
    assert_respond_to(object, name)
    assert(object.public_send(name))
  end
end
