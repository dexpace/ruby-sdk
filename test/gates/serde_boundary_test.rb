# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../support/gate_case"
require_relative "../../tools/serde_boundary"

# SSE-37's mechanism, and the phase-7 segmentation design's spec-forced boundary 5: core's SSE
# layer -- and, once 7c lands, its pagination layer -- holds no serialization dependency, checked
# by a PARSED scan of every require, every constant read and every RBS type name under the
# guarded paths. The gate that would have caught a `require "json"` or a `Dexpace::Serde`
# reference the require allowlist cannot see, because the seam is core's own.
class SerdeBoundaryTest < GateCase
  FIXTURES = File.join(ROOT, "test/fixtures/gates/serde_boundary")

  test "the real repository is clean, and its pending rows are the pagination layer's" do
    assert_empty(SerdeBoundary.violations(ROOT))
    assert_equal(%w[gems/dexpace-core/lib/dexpace/page/**/*.rb
                    gems/dexpace-core/sig/dexpace/page/**/*.rbs],
                 SerdeBoundary.pending(ROOT).map(&:first),)
  end

  test "every GUARDED glob matches at least one real file, so the boundary checks something" do
    SerdeBoundary::GUARDED.map(&:first).each do |glob|
      refute_empty(Dir.glob(File.join(ROOT, glob)), glob)
    end
  end

  # The four spellings a require takes, plus autoload: the scan reads parsed call nodes.
  test "rejects every spelling of a serialization require, naming SSE-37 and the line" do
    {
      "requires_json.rb" => 'require "json"',
      "requires_json_parenthesised.rb" => 'require "json"',
      "kernel_receiver.rb" => 'require "json/ext"',
      "autoload_json.rb" => 'autoload "json"',
      "requires_serde_relative.rb" => 'require_relative "../serde/json"',
      "requires_dexpace_serde.rb" => 'require "dexpace/serde"',
    }.each do |fixture, fragment|
      found = scan(fixture)

      assert_includes(found, fragment, fixture)
      assert_includes(found, "SSE-37", fixture)
      assert_includes(found, "#{fixture}:4:", fixture)
    end
  end

  test "rejects a serde constant in every spelling, the qualified ::JSON included" do
    {
      "names_serde.rb" => "Dexpace::Serde",
      "names_bare_serde.rb" => "Serde",
      "names_qualified_json.rb" => "::JSON",
      "names_bare_json.rb" => "JSON",
      "names_nested_path.rb" => "Dexpace::Serde::JSON::Codec",
      "names_dynamic_parent.rb" => "self::JSON",
    }.each do |fixture, rendered|
      found = scan(fixture)

      assert_includes(found, "names the constant #{rendered}", fixture)
      assert_includes(found, "SSE-37", fixture)
    end
  end

  # The parsed scan is what lets the guarded YARD say the words the requirement asks for.
  test "a comment or a string naming a serde constant or feature is not a dependency" do
    assert_empty(scan("comment_only.rb"))
    assert_empty(scan("string_only.rb"))
    assert_empty(scan("comment_only.rbs"))
  end

  test "accepts a clean guarded file and a clean guarded signature" do
    assert_empty(scan("clean.rb"))
    assert_empty(scan("clean.rbs"))
  end

  test "rejects a serde type name in a guarded signature" do
    assert_includes(scan("names_serde.rbs"), "names the type Serde")
    assert_includes(scan("names_json.rbs"), "names the type JSON")
    assert_includes(scan("names_json.rbs"), "names_json.rbs:4:")
  end

  test "refuses a file it cannot read rather than passing it" do
    assert_includes(scan("unparseable.rb"), "cannot read it")
    assert_includes(scan("dynamic_feature.rb"), "not a string literal")
  end

  test "the feature screen catches json, json/*, and any serde path segment, and nothing else" do
    %w[json json/ext dexpace/serde dexpace/serde/json ../serde/json].each do |feature|
      assert(SerdeBoundary.forbidden_feature?(feature), "#{feature} should be forbidden")
    end
    %w[dexpace/sse dexpace/io/buffered_source uri jsonish/thing serdette].each do |feature|
      refute(SerdeBoundary.forbidden_feature?(feature), "#{feature} should pass")
    end
  end

  test "a GUARDED glob matching no file is a violation naming the glob, never a silent pass" do
    found = SerdeBoundary.violations(File.join(FIXTURES, "empty_glob"))

    assert_equal(1, found.size)
    assert_includes(found.first, "gems/dexpace-core/lib/dexpace/sse/**/*.rb")
    assert_includes(found.first, "matches no file")
  end

  test "the gate task fails on a fixture workspace, naming the file and line, and passes here" do
    _out, err, status = rake("gates:serde_boundary",
                             "DEXPACE_GATE_ROOT" => File.join(FIXTURES, "workspace"),)

    refute_predicate(status, :success?)
    assert_includes(err, "lib/dexpace/sse/reader.rb:4: require \"json\"")
    assert_includes(err, "SSE-37")

    out, err, status = rake("gates:serde_boundary")

    assert_predicate(status, :success?, err)
    assert_includes(out, "4 guarded globs clean")
    assert_includes(out, "PENDING gems/dexpace-core/lib/dexpace/page/**/*.rb")
  end

  private

  def scan(fixture)
    SerdeBoundary.scan_file(File.join(FIXTURES, "files", fixture), requirement: "SSE-37").join("\n")
  end
end
