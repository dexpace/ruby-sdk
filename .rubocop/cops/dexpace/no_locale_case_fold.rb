# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # HTTP-13 folds header names with ASCII rules. Ruby's fold is opt-in-locale --
      # `"I".downcase(:turkic)` is `"ı"` -- and the locale symbol is the only argument the fold
      # family accepts, so any argument at all is the offence. `casecmp?` is banned for the same
      # reason one method along: it applies Unicode full case folding, where `casecmp` is
      # ASCII-only.
      class NoLocaleCaseFold < Base
        FOLD_MSG = "Call `%<method>s` with no argument: Ruby's fold is opt-in-locale and " \
                   "HTTP-13 needs ASCII folding."
        CASECMP_MSG = "Use `casecmp`, which is ASCII-only; `casecmp?` applies Unicode full " \
                      "case folding (HTTP-13)."
        FOLDS = %i[
          downcase downcase! upcase upcase! capitalize capitalize! swapcase swapcase!
        ].freeze
        RESTRICT_ON_SEND = (FOLDS + %i[casecmp?]).freeze

        def on_send(node)
          if node.method?(:casecmp?)
            add_offense(node, message: CASECMP_MSG)
          elsif FOLDS.include?(node.method_name) && !node.arguments.empty?
            add_offense(node, message: format(FOLD_MSG, method: node.method_name))
          end
        end
        alias on_csend on_send
      end
    end
  end
end
