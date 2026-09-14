# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"

# Design §9.2's third check. The gemspec audit sees declarations and the allowlist audit sees
# text; only Bundler refusing to activate an undeclared gem catches a transitive require reached
# at load time.
class CleanBundleTest < GateCase
  test "every gem loads inside a bundle that holds only itself" do
    out, err, status = rake("gates:clean_bundle")

    assert_predicate(status, :success?, err)
    assert_includes(out, "6 gem(s) load in isolation")
  end

  # The refusal is Bundler's, and Bundler can refuse `logger` only on a Ruby where it has left
  # the default set: a default gem's files sit on the stdlib load path, which no bundle removes.
  # That is why design §9.2 makes the 4.0 row load-bearing, and why this case names its
  # condition on the rows where it cannot bite rather than failing there.
  test "an undeclared require fails under Bundler" do
    since = defined?(Gem::BUNDLED_GEMS::SINCE) ? Gem::BUNDLED_GEMS::SINCE["logger"] : nil
    unless since && Gem::Version.new(RUBY_VERSION) >= Gem::Version.new(since)
      skip("logger is still a default gem on Ruby #{RUBY_VERSION} (bundled at #{since || "4.0.0"})")
    end

    Dir.mktmpdir("dexpace-clean-bundle-fixture") do |dir|
      # A complete miniature workspace: the gem, the VERSIONS file its gemspec reads, and the
      # reader that parses it. Without these two the gemspec raises before `logger` is reached.
      FileUtils.mkdir_p(File.join(dir, "gems"))
      FileUtils.cp_r(File.join(ROOT, "gems/dexpace-core"), File.join(dir, "gems"))
      FileUtils.cp_r(File.join(ROOT, "tools"), dir)
      FileUtils.cp(File.join(ROOT, "VERSIONS"), dir)

      target = File.join(dir, "gems/dexpace-core/lib/dexpace.rb")
      File.write(target, "#{File.read(target)}\nrequire \"logger\"\n")

      _out, err, status = rake(
        "gates:clean_bundle", "DEXPACE_CLEAN_BUNDLE_GEM" => File.join(dir, "gems/dexpace-core"),
      )

      refute_predicate(status, :success?)
      assert_includes(err, "logger")
    end
  end
end
