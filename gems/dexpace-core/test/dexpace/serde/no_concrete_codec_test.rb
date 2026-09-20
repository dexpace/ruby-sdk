# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require "ripper"

# SEAM-2, and the phase-7 charter's cross-cutting constraint: "Dexpace::Serde::JSON appears in no
# core file, in no core sig/ file (NFR-11) and in no core test." No other gate sees this inside one
# gem -- the require allowlist denies `json` by name but says nothing about a CONSTANT reference,
# and Steep type-checks core against core's own sig/ where the constant does not exist either.
#
# The scan reads CODE, not comments: lib/dexpace/serde.rb and lib/dexpace/http/method.rb both
# name the adapter in a comment explaining the shadowing hazard, which is exactly the kind of
# sentence a reader needs and not a dependency. Ruby files are tokenised with Ripper (stdlib on
# every supported Ruby) and their comment tokens dropped; .rbs files drop `#` comment lines.
class DexpaceSerdeNoConcreteCodecTest < DexpaceTestCase
  ROOT = File.expand_path("../../..", __dir__)
  TREES = %w[lib sig test].freeze
  SELF = File.expand_path(__FILE__)

  test "no core file, signature or test names the concrete codec outside a comment" do
    offenders = TREES.flat_map do |tree|
      Dir.glob(File.join(ROOT, tree, "**", "*")).select do |path|
        File.file?(path) && File.expand_path(path) != SELF && code_of(path).include?("Serde::JSON")
      end
    end

    assert_empty(offenders, "SEAM-2: core must name no concrete codec")
  end

  test "the seam itself supplies no media type to fall back to" do
    refute_respond_to(Dexpace::Serde, :media_type, "SEAM-19, restated at phase 7's first consumer")
  end

  private

  def code_of(path)
    source = File.read(path)
    return source.lines.grep_v(/\A\s*#/).join if path.end_with?(".rbs")
    return source unless path.end_with?(".rb")

    Ripper.lex(source).reject { |(_, type, _)| type == :on_comment }.map { |token| token[2] }.join
  end
end
