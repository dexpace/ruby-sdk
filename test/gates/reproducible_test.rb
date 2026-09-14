# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/reproducible"

# NFR-12: identical source inputs yield byte-for-byte identical artifacts. Scope is one gem,
# built twice, on one interpreter -- cross-RubyGems-version container identity is the
# toolchain's business, not the source's, and is not claimed (design Deviation Ledger P0-7).
class ReproducibleTest < GateCase
  FIXTURE = File.join(ROOT, "test/fixtures/gates/reproducible/gems/nondeterministic")
  CLOCK_DEPENDENT = File.join(ROOT, "test/fixtures/gates/reproducible/gems/clock_dependent")

  test "building each gem twice under a fixed SOURCE_DATE_EPOCH gives identical bytes" do
    out, err, status = rake("gates:reproducible")

    assert_predicate(status, :success?, err)
    assert_includes(out, "6 gems, byte-identical")
  end

  test "the comparison notices a gem whose build depends on the clock" do
    # A gemspec that reads the clock produces a different metadata.gz every build, epoch or no
    # epoch: the input no normalisation can repair, and the one that proves the digests are
    # compared rather than assumed equal.
    first, second = Reproducible.digests(CLOCK_DEPENDENT, epoch: Reproducible::EPOCH)

    refute_equal(
      first, second,
      "two builds of a clock-dependent gem agreed; the digest is not sensitive to the build " \
      "and this gate proves nothing",
    )
  end

  # A pinned toolchain fact, because the plan's negative fixture -- a file touched between two
  # builds -- cannot fail under the epoch the gate always sets: `gem build` writes every tar
  # entry's mtime as Gem.source_date_epoch, so the touched file's own mtime never reaches the
  # artifact. That is the half of NFR-12 the toolchain already pays for.
  test "a moved mtime never changes the artifact under a fixed epoch" do
    first, second = digests_around_a_touch(Reproducible::EPOCH)

    assert_equal(first, second)
  end

  # What Gem.source_date_epoch falls back to with the variable UNSET depends on RubyGems, not on
  # the gate: from RubyGems 3.6 (the 3.4 and 4.0 rows) it is the fixed
  # Gem::DEFAULT_SOURCE_DATE_EPOCH, 1980-01-02, and two builds still agree; on 3.4.19 and 3.5.22
  # (the 3.2 and 3.3 rows) it is Time.now, memoised per process, so two builds in separate
  # processes differ across a second boundary. The gate never depends on the fallback -- it sets
  # the epoch -- so the unset case is asserted only where the fallback is fixed, and skipped with
  # its reason where it is the clock.
  test "with the epoch unset, a RubyGems that falls back to a fixed epoch still agrees" do
    unless defined?(Gem::DEFAULT_SOURCE_DATE_EPOCH)
      skip("RubyGems #{Gem::VERSION} falls back to Time.now when SOURCE_DATE_EPOCH is unset")
    end

    first, second = digests_around_a_touch(nil)

    assert_equal(first, second)
  end

  test "the fixed epoch and an unset one embed different timestamps" do
    with_epoch, = Reproducible.digests(FIXTURE, epoch: Reproducible::EPOCH)
    without_epoch, = Reproducible.digests(FIXTURE, epoch: nil)

    refute_equal(with_epoch, without_epoch)
  end

  # `epoch: nil` means UNSET for the subprocess, not "inherit": an empty env hash would let a
  # SOURCE_DATE_EPOCH exported by the developer's shell through, and the two unset cases above
  # would then measure that shell. Exporting the gate's own epoch is the value that would hide
  # it, so that is the one the test exports.
  test "an epoch exported by the parent shell does not reach an unset build" do
    exported = ENV.fetch("SOURCE_DATE_EPOCH", nil)
    ENV["SOURCE_DATE_EPOCH"] = Reproducible::EPOCH
    with_epoch, = Reproducible.digests(FIXTURE, epoch: Reproducible::EPOCH)
    without_epoch, = Reproducible.digests(FIXTURE, epoch: nil)

    refute_equal(with_epoch, without_epoch)
  ensure
    exported.nil? ? ENV.delete("SOURCE_DATE_EPOCH") : ENV["SOURCE_DATE_EPOCH"] = exported
  end

  test "the gate task goes red on a workspace whose gem does not rebuild identically" do
    workspace = File.join(ROOT, "test/fixtures/gates/reproducible")
    _out, err, status = rake("gates:reproducible", "DEXPACE_GATE_ROOT" => workspace)

    refute_predicate(status, :success?)
    assert_includes(err, "built two different artifacts")
  end

  test "bundler-audit is wired into the default gate set and runs against a fresh resolve" do
    body = File.read(File.join(ROOT, "tasks/quality.rake"))

    assert_includes(body, "bundler-audit")
    assert_includes(body, "--update")
    assert_includes(File.read(File.join(ROOT, "Rakefile")), "bundler_audit")
  end

  private

  # Two builds with the fixture's one source file touched between them, its mtime restored after.
  def digests_around_a_touch(epoch)
    source = File.join(FIXTURE, "lib/nondeterministic.rb")
    Reproducible.digests(FIXTURE, epoch: epoch) { FileUtils.touch(source, mtime: Time.now + 3600) }
  ensure
    FileUtils.touch(source, mtime: Time.now)
  end
end
