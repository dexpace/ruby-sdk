# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "pathname"
require "rbs"

# The body of gates:spdx_rbs (phase 10, design addendum A8; NFR-13, NFR-3).
#
# NFR-13's conformance clause is "scan ALL source files for the required header", and sig/ ships
# inside every gem, so the signatures are shipped source. Phase 0 mechanised the header as a
# RuboCop cop, and a cop parses Ruby -- it cannot reach a .rbs file, which is how 307 shipped
# signatures went out with none (phase 9's aggregate run, 2026-09-23). The header is ONE line:
# `# frozen_string_literal: true` has no meaning in RBS.
#
# The second assertion -- no shipped signature declares nothing -- is NFR-3's: an empty .rbs passes
# `rbs validate` and `steep check` and tells a consumer's type checker nothing. On rbs 4.2.0
# `RBS::Parser.parse_signature` returns `[buffer, directives, declarations]`, and the plan's
# `.flatten.compact.empty?` is never true because the Buffer survives the flatten (measured on an
# empty string and on a comment-only file). The declarations are the third element.
module SpdxRbs
  HEADER = "# SPDX-License-Identifier: MIT"
  GLOB = "gems/*/sig/**/*.rbs"

  def self.offences(root:, paths: Dir.glob(File.join(root, GLOB)))
    paths.flat_map { |path| offences_in(path) }
  end

  def self.offences_in(path)
    source = File.read(path)
    out = []
    out << "#{path}: line 1 is not `#{HEADER}` (NFR-13)" unless source.lines.first&.chomp == HEADER
    _buffer, _directives, declarations = RBS::Parser.parse_signature(
      RBS::Buffer.new(name: Pathname(path), content: source),
    )
    out << "#{path}: declares nothing (NFR-3)" if declarations.empty?
    out
  rescue RBS::ParsingError => error
    ["#{path}: does not parse -- #{error.message}"]
  end
end
