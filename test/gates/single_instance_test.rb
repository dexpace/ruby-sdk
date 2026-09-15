# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# Design §2.4's single-instance guarantee, and §9's table row for it: "the auditable form of a
# claim §2.4 otherwise argues structurally." Type-identity checks -- XCUT-4's exception
# hierarchy, RECOV-1's Outcome variants, SERDE-14's Tristate -- break silently under duplication.
class SingleInstanceTest < GateCase
  test "one resolved path per core file, and VERSION agrees with the gemspec" do
    _out, err, status = rake("gates:single_instance")

    assert_predicate(status, :success?, err)
  end

  test "a duplicated feature path fails the gate" do
    _out, err, status = rake("gates:single_instance", "DEXPACE_FORCE_DUPLICATE" => "1")

    refute_predicate(status, :success?)
    assert_includes(err, "loaded twice")
  end

  # The case §2.4 argues against, produced for real rather than simulated: a second copy of
  # core's lib/ -- a vendored copy beside a gem-installed one -- preloaded through RUBYOPT, so
  # the gate's subprocess holds two resolved paths for each core feature. Ruby's require never
  # records one path twice, which is why the tally is keyed on the feature and not the path.
  # Since phase 1 the second copy cannot finish loading at all: its first `Data.define` model
  # re-opens a class with a fresh superclass and Ruby raises `superclass mismatch`, so the gate
  # names that as well, and the top-level entry file is never provided twice -- the features
  # loaded before the mismatch are.
  test "the same core feature loaded from two directories fails the gate" do
    Dir.mktmpdir("dexpace-vendored-core") do |dir|
      FileUtils.cp_r(File.join(ROOT, "gems/dexpace-core/lib"), dir)
      preload = "-W0 -r#{File.join(dir, "lib/dexpace")}"
      _out, err, status = rake("gates:single_instance", "RUBYOPT" => preload)

      refute_predicate(status, :success?)
      both = "#{dir}/lib/dexpace/version.rb and #{ROOT}/gems/dexpace-core/lib/dexpace/version.rb"

      assert_includes(err, "loaded twice: dexpace/version.rb from #{both}")
      assert_includes(err, "a model re-opened from the second copy")
      assert_includes(err, "superclass mismatch")
    end
  end

  test "a VERSION literal that disagrees with its gemspec fails the gate" do
    fixture = File.join(ROOT, "test/fixtures/gates/single_instance/version_skew")
    _out, err, status = rake("gates:single_instance", "DEXPACE_GATE_ROOT" => fixture)

    refute_predicate(status, :success?)
    assert_includes(err, "VERSION 9.9.9 != gemspec 0.0.0")
  end
end
