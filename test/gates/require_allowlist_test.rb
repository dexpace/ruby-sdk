# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/require_allowlist"

# Design §9.2's require-allowlist audit, the one gate with no counterpart in the reference build.
# Extended here to every gem, not core alone -- an adapter's undeclared require is invisible
# until a Ruby where the name is bundled (design's §9 Addendum A2).
class RequireAllowlistTest < GateCase
  FIXTURES = "test/fixtures/gates/require_allowlist"

  # Three of the cases below assert the *reason* a name is refused, and that reason is read from
  # Gem::BUNDLED_GEMS::SINCE, which does not exist on Ruby 3.2. On that row the name is still
  # refused -- it is simply not allowlisted -- so the gate holds; only the message differs.
  def skip_without_bundled_table
    skip("Gem::BUNDLED_GEMS::SINCE is undefined on Ruby 3.2") unless RequireAllowlist.bundled?
  end

  test "the real repository is clean" do
    assert_empty(RequireAllowlist.violations(ROOT))
  end

  test "rejects a name that became bundled at 3.4" do
    skip_without_bundled_table

    assert_includes(scan("base64.rb"), "bundled since 3.4.0")
  end

  test "rejects a name that becomes bundled at 4.0" do
    skip_without_bundled_table

    assert_includes(scan("logger.rb"), "bundled since 4.0.0")
  end

  test "rejects tsort, which is default on every supported Ruby and bundled at 4.1" do
    skip_without_bundled_table

    assert_includes(scan("tsort.rb"), "bundled since 4.1.0")
  end

  test "refuses base64, logger and tsort on every Ruby, whatever the message says" do
    %w[base64.rb logger.rb tsort.rb].each { |fixture| refute_empty(scan(fixture), fixture) }
  end

  test "rejects json by name, with the requirement that forbids it" do
    assert_includes(scan("json.rb"), "SEAM-2")
  end

  test "rejects timeout by name, with the section that forbids it" do
    assert_includes(scan("timeout.rb"), "§8.3")
  end

  test "a denial with a scope binds the gems inside it" do
    assert_includes(scan("socket.rb", gem: "dexpace-core"), "SEAM-1/SEAM-2")
    assert_includes(scan("socket.rb", gem: "dexpace-transport-net_http"), "SEAM-1/SEAM-2")
  end

  test "a denial with a scope does not reach a gem outside it" do
    assert_empty(scan("socket.rb", gem: "dexpace-conformance"))
  end

  # A scoped-out denial is an implicit permission for every gem outside the scope, so only the
  # name the amendment argued for -- socket, for the conformance gem's wire server -- carries
  # one. The rest of the transport family is denied everywhere.
  test "the transport names other than socket are denied to every gem" do
    %w[dexpace-core dexpace-transport-net_http dexpace-serde-json dexpace-conformance].each do |gem|
      assert_includes(scan("net_http.rb", gem: gem), "SEAM-1/SEAM-2", gem)
    end
  end

  test "a denial with no scope, and a scan naming no gem, are both strict" do
    assert_includes(scan("json.rb", gem: "dexpace-conformance"), "SEAM-2")
    assert_includes(scan("socket.rb"), "SEAM-1/SEAM-2")
  end

  # The scan reads parsed call nodes, so every ordinary spelling of a denied require is refused,
  # not only a bare `require` at the head of a line -- a parenthesised call, the Kernel receiver,
  # a require after a `;`, and `autoload`, which is a deferred require of its second argument.
  test "refuses every ordinary spelling of a denied require" do
    {
      "parenthesised.rb" => "SEAM-2",
      "kernel_receiver.rb" => "SEAM-2",
      "mid_line.rb" => "§8.3",
      "autoload.rb" => "SEAM-2",
    }.each { |fixture, fragment| assert_includes(scan(fixture), fragment, fixture) }
  end

  test "refuses a feature it cannot read rather than passing it" do
    %w[dynamic.rb interpolated.rb].each do |fixture|
      assert_includes(scan(fixture), "not a string literal", fixture)
    end
  end

  test "a comment naming a denied feature is not a require" do
    assert_empty(scan("comment_only.rb"))
  end

  test "names the line of the offending call" do
    assert_includes(scan("mid_line.rb"), "mid_line.rb:5: require \"timeout\"")
  end

  test "rejects a require_relative that escapes the gem's lib/" do
    assert_includes(scan("escaping_relative.rb"), "escapes")
    assert_includes(scan("parenthesised_relative.rb"), "escapes")
  end

  test "accepts a require_relative that stays inside lib/" do
    assert_empty(scan("internal_relative.rb"))
  end

  # The fixture's third require is `tempfile`, phase 8a's one-line growth of the allowlist
  # (TRANSPORT-28): a default gem on every supported Ruby that no row of Gem::BUNDLED_GEMS::SINCE
  # names -- the bundled-table case below is what keeps that true on every CI row -- so
  # dexpace-conformance may create the file its file-body assertion uploads a window of, and
  # core is no wider for it (nothing in core requires it).
  test "accepts an allowlisted name and a dexpace/ path" do
    assert_empty(scan("allowed.rb"))
  end

  test "accepts core's own entry point, which an adapter requires as `dexpace`" do
    assert_empty(scan("core_entry.rb", gem: "dexpace-transport-net_http"))
  end

  test "every allowlisted name requires cleanly on this interpreter" do
    RequireAllowlist::ALLOWED.each { |name| require name }
  end

  test "no allowlisted name is a bundled gem on this interpreter" do
    skip_without_bundled_table

    overlap = RequireAllowlist::ALLOWED & RequireAllowlist.bundled_since.keys

    assert_empty(overlap, "allowlisted and bundled: #{overlap.join(", ")}")
  end

  test "the gate task fails on a fixture workspace and passes on the repository" do
    _out, err, status = rake(
      "gates:require_allowlist", "DEXPACE_GATE_ROOT" => File.join(ROOT, FIXTURES, "workspace"),
    )

    refute_predicate(status, :success?)
    assert_includes(err, "§8.3")

    out, err, status = rake("gates:require_allowlist")

    assert_predicate(status, :success?, err)
    assert_includes(out, "clean on Ruby")
  end

  private

  def scan(fixture, gem: nil)
    path = File.join(ROOT, FIXTURES, fixture)
    RequireAllowlist.scan_file(path, permitted: [], lib_root: File.dirname(path), gem: gem)
      .join("\n")
  end
end
