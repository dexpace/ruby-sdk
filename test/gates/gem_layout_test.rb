# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/versions"

# Design §2.3's layout, asserted rather than assumed. The housekeeping probe's `readmes` check
# enforces the README half independently; this covers the rest.
class GemLayoutTest < GateCase
  ENTRIES = {
    "dexpace-core" => "lib/dexpace.rb",
    "dexpace-transport-net_http" => "lib/dexpace/transport/net_http.rb",
    "dexpace-transport-async_http" => "lib/dexpace/transport/async_http.rb",
    "dexpace-serde-json" => "lib/dexpace/serde/json.rb",
    "dexpace-async-thread" => "lib/dexpace/async/thread.rb",
    "dexpace-conformance" => "lib/dexpace/conformance.rb",
  }.freeze

  test "VERSIONS names exactly the six MVP gems, and each has a directory" do
    assert_equal(ENTRIES.keys.sort, DexpaceVersions.gem_names.sort)
    assert_equal(ENTRIES.keys.sort, Dir.children(File.join(ROOT, "gems")).sort)
  end

  test "every gem carries a gemspec, a README, a LICENSE and a Rakefile" do
    ENTRIES.each_key do |gem|
      %W[#{gem}.gemspec README.md LICENSE Rakefile].each do |file|
        assert_path_exists(File.join(ROOT, "gems", gem, file))
      end
    end
  end

  test "every gem's entry file exists and has a sig mirror, one file per file" do
    ENTRIES.each do |gem, entry|
      root = File.join(ROOT, "gems", gem)

      assert_path_exists(File.join(root, entry))
      lib = Dir.glob("lib/**/*.rb", base: root).sort
      sig = Dir.glob("sig/**/*.rbs", base: root).sort

      assert_equal(
        lib.map { |f| f.delete_prefix("lib/").delete_suffix(".rb") },
        sig.map { |f| f.delete_prefix("sig/").delete_suffix(".rbs") },
      )
    end
  end

  test "every gem's LICENSE is byte-identical to the repository's" do
    expected = File.read(File.join(ROOT, "LICENSE"))

    ENTRIES.each_key do |gem|
      assert_equal(expected, File.read(File.join(ROOT, "gems", gem, "LICENSE")), gem)
    end
  end
end
