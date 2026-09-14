# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # OBS-25 ("selecting a no-op path MUST NOT allocate per call") and OBS-1 (a disabled log
      # event "MUST allocate nothing"). A `**` rest-keyword parameter allocates a Hash on every
      # call, including a call that passes no keyword at all -- measured at one object per call
      # on 3.4.10 -- so no method written with one can satisfy either requirement, and the
      # failure is silent: every behavioural test passes and only an allocation count fails.
      # `api-design/1d9e6e0b`'s backward-compatibility argument is a property of NAMED keywords,
      # which a splat does not share, so the fix the message names is the named form.
      #
      # Public methods only: a private helper's allocation is its caller's to account for, and
      # the caller is the public method this cop already reaches. And library code only --
      # .rubocop.yml scopes the cop to gems/*/lib/**/*.rb -- because the two requirements are
      # allocation assertions on the SDK's own no-op paths, not on a test helper or a tool.
      class NoKeywordSplat < Base
        include VisibilityHelp

        MSG = "`**%<name>s` allocates a Hash on every call, even one passing no keyword, which " \
              "OBS-25 forbids on a no-op path. Name each keyword (`%<name>s: nil`) instead."

        def on_def(node)
          check(node) if node_visibility(node) == :public
        end

        def on_defs(node)
          check(node) unless private_singleton?(node)
        end

        private

        def check(node)
          splat = node.arguments.find(&:kwrestarg_type?)
          return if splat.nil?

          add_offense(splat, message: format(MSG, name: splat.name || "options"))
        end

        # `private` does not reach a singleton method; `private_class_method` does, inline
        # (`private_class_method def self.x`) or by name after the definition.
        def private_singleton?(node)
          return true if private_class_method_inline?(node.parent)

          node.right_siblings.any? do |sibling|
            private_class_method_by_name?(sibling, method_name: node.method_name)
          end
        end

        # @!method private_class_method_inline?(node)
        def_node_matcher :private_class_method_inline?, "(send nil? :private_class_method defs)"

        # @!method private_class_method_by_name?(node, method_name:)
        def_node_matcher :private_class_method_by_name?, <<~PATTERN
          (send nil? :private_class_method <(sym %method_name) ...>)
        PATTERN
      end
    end
  end
end
