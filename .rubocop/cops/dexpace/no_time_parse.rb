# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Design §3.5. `Time.parse` guesses at an ambiguous string and its behaviour is locale-
      # and version-sensitive; an HTTP date is a fixed grammar and is parsed with
      # `Time.httpdate` or an explicit format.
      class NoTimeParse < Base
        MSG = "`%<offender>s` is banned: parse HTTP dates explicitly with `Time.httpdate` " \
              "or a fixed format (design §3.5)."
        RESTRICT_ON_SEND = %i[parse].freeze

        # @!method banned_parse?(node)
        def_node_matcher :banned_parse?, <<~PATTERN
          ({send csend} (const {nil? cbase} {:Time :Date :DateTime}) :parse ...)
        PATTERN

        def on_send(node)
          return unless banned_parse?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end
        alias on_csend on_send
      end
    end
  end
end
