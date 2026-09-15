# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/inline_executor"
require "dexpace"

# SEAM-1 and SEAM-2 as properties of the assembled tree rather than of any one file. The three
# mechanised gates phase 0 built cover the dependency half; this covers the part a gate cannot see.
class DexpaceSeamSurfaceTest < DexpaceTestCase
  SEAMS = [Dexpace::Transport, Dexpace::AsyncTransport, Dexpace::Serde].freeze
  ENTRY_POINTS = %i[conforms? register install resolve registered_keys swap].freeze
  # Every concrete implementation SEAM-2 could tempt an error message into naming.
  CONCRETE = %r{net_http|async_http|net/http|async-http|\bjson\b|\boj\b|httpx|excon|typhoeus}i

  test "every seam registry starts empty on a bare require" do
    SEAMS.each { |seam| assert_empty(seam.registered_keys, "#{seam} is not empty") }
  end

  test "no seam's zero-candidate error names a concrete gem" do
    SEAMS.each do |seam|
      error = assert_raises(Dexpace::SeamError) { seam.resolve }

      refute_match(CONCRETE, error.message,
                   "SEAM-2: #{seam} names a concrete implementation in its error path",)
    end
  end

  test "every seam has the same five registry entry points and a conformance predicate" do
    SEAMS.each do |seam|
      ENTRY_POINTS.each { |name| assert_respond_to(seam, name, "#{seam}.#{name}") }
    end
  end

  test "core defines no auto-activation hook, deliberately" do
    # Design §3.6 permits presence-gated auto-activation for instrumentation only, and phase 2
    # ships no instrumentation seam, so there is nothing to activate. It is recorded under
    # docs/first-release.md § What v1 ships without (post-v1; otel is its only sanctioned user), so
    # a later phase reading §3.6 does not conclude it was forgotten.
    SEAMS.each do |seam|
      refute_respond_to(seam, :install_if_present, "#{seam} grew an auto-activation hook")
      refute_respond_to(seam, :auto_activate, "#{seam} grew an auto-activation hook")
    end
  end

  # gates:require_allowlist is the blocking version of this; the assertion here is the narrower
  # one the design states -- phase 1's two requires are still the only ones outside
  # require_relative, and phase 2 added none.
  test "core requires nothing outside its own tree beyond phase 1's two stdlib features" do
    requires = Dir.glob(File.expand_path("../../lib/**/*.rb", __dir__))
      .flat_map { |path| File.readlines(path) }
      .grep(/^\s*require\s+["']/)
      .map { |line| line[/["']([^"']+)["']/, 1] }
      .uniq
      .sort

    assert_equal(%w[strscan uri], requires,
                 "SEAM-1: the only non-relative requires in core are phase 1's, both on the " \
                 "allowlist; phase 2 added none",)
  end

  test "the seam modules expose no instance side to be included by accident" do
    SEAMS.each do |seam|
      assert_empty(seam.instance_methods(false), "#{seam} is a singleton module, not a mixin")
    end
  end

  test "both SEAM-18 bridges live under Dexpace::Bridge, not beside an adapter namespace" do
    async = Dexpace::Transport.async_over(->(_r, _o, _c) {}, executor: InlineExecutor.new)
    sync = Dexpace::AsyncTransport.sync_over(->(_r, _o, _c) {})

    assert_instance_of(Dexpace::Bridge::AsyncOver, async)
    assert_instance_of(Dexpace::Bridge::SyncOver, sync)
    refute(Dexpace::Transport.const_defined?(:AsyncOver, false), "deviation P2-1 and P2-13")
    refute(Dexpace::AsyncTransport.const_defined?(:SyncOver, false))
    refute(Dexpace::Transport.const_defined?(:Async, false), "deviation P2-1")
  end

  # The three registries are three instances of one class, which is what XCUT-23's deterministic
  # single-implementation resolution rests on for phase 9.
  test "the three seams hold three distinct registries of one class" do
    registries = SEAMS.map { |seam| seam.const_get(:REGISTRY, false) }

    assert_equal(3, registries.map(&:object_id).uniq.size)
    registries.each { |registry| assert_instance_of(Dexpace::Registry, registry) }
    assert_equal(["transport", "async transport", "codec"], registries.map(&:seam))
  end
end
