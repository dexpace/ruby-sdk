# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # NFR-13, plus styleguide 1.4's header shape. The reference enforces the licence header as
      # a review convention; this port enforces it mechanically, because a SHOULD carried by
      # convention across six gems and ten phases is a SHOULD that decays.
      #
      # Line 2 is the SPDX identifier because there is no `# typed:` sigil in this repository to
      # occupy that slot (docs/knowledge/notes/formatting-and-tooling.md). Line 1 stays the
      # frozen-string-literal comment: Style/FrozenStringLiteralComment requires it to be present
      # but not to be first, and styleguide rule 1.4 requires it to be the very first line
      # (`formatting-and-tooling/bf14bf0e`), so pinning the position is this cop's job.
      class SpdxHeader < Base
        FROZEN = "# frozen_string_literal: true"
        SPDX = "# SPDX-License-Identifier: MIT"
        MSG_FROZEN = "Line 1 must be `#{FROZEN}` (styleguide 1.4).".freeze
        MSG_SPDX = "Line 2 must be `#{SPDX}` (NFR-13).".freeze
        MSG_BLANK = "Line 3 must be blank, separating the header block from the file's content."

        def on_new_investigation
          lines = processed_source.lines
          return if lines.empty?

          expect_line(lines, 1, FROZEN, MSG_FROZEN)
          expect_line(lines, 2, SPDX, MSG_SPDX)
          expect_line(lines, 3, "", MSG_BLANK) if lines.length >= 3
        end

        private

        # Reports `message` on line `number` unless that line is exactly `expected` -- or, when
        # `expected` is the empty string, unless it is blank. A line past the end of the file is
        # reported on the last line there is, so a one-line file still points somewhere.
        def expect_line(lines, number, expected, message)
          actual = lines[number - 1].to_s
          return if expected.empty? ? actual.strip.empty? : actual == expected

          add_offense(
            processed_source.buffer.line_range([number, lines.length].min),
            message: message,
          )
        end
      end
    end
  end
end
