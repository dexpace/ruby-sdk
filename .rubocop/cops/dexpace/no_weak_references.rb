# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # CTX-19: "reimplementations MUST NOT hold contexts by weak/soft references ... and MUST
      # treat the bounded cap (CTX-11), not garbage collection, as the leak backstop." Design
      # §5.4 makes that a lint rule; this is the eighth custom cop (phase 4a, P4-10), a ban list
      # with a stated hazard in the shape of Dexpace/NoThreadInterrupt and named after its own
      # rule, because every cop here mechanises exactly one.
      #
      # A source-text cop rather than a runtime check, because RuboCop parses and never
      # evaluates: the suite's rejected rows include ObjectSpace::WeakKeyMap, which is UNDEFINED
      # on the 3.2.11 floor, and RuboCop::ProcessedSource at TargetRubyVersion 3.2 reports
      # valid_syntax? and yields the const nodes this cop matches on for every row regardless.
      #
      # Three spellings: a constant reference to ObjectSpace::WeakMap or ::WeakKeyMap (qualified,
      # cbase-qualified, or bare and lexically inside `module ObjectSpace`); a reference to
      # WeakRef, bare or cbase-qualified; and `require "weakref"` -- bare, parenthesised, or
      # through `Kernel.require` / `::Kernel.require`, and nothing else. An `autoload :WeakRef,
      # "weakref"` is NOT matched here: it names the constant as a Symbol, and the reference
      # that later triggers it is one the second spelling flags, so the autoload form needs no
      # row of its own. The last spelling is redundant inside dexpace-core, where
      # gates:require_allowlist already rejects it, and is not redundant anywhere else -- the
      # allowlist covers core's lib/ alone, which is why .rubocop.yml scopes this cop to every
      # gem's lib/. Neither this cop nor the CTX-19 reachability test can see a third-party
      # store: a reimplementation is by definition outside these gates.
      class NoWeakReferences < Base
        MSG = "`%<offender>s` is forbidden: a context must not be held by a weak reference " \
              "(CTX-19); the bounded cap (CTX-11) is the leak backstop."

        RESTRICT_ON_SEND = %i[require].freeze
        WEAK_MAP_NAMES = %i[WeakMap WeakKeyMap].freeze

        # @!method object_space_weak_map?(node)
        def_node_matcher :object_space_weak_map?, <<~PATTERN
          (const (const {nil? cbase} :ObjectSpace) {:WeakMap :WeakKeyMap})
        PATTERN

        # @!method weak_ref_const?(node)
        def_node_matcher :weak_ref_const?, "(const {nil? cbase} :WeakRef)"

        # @!method weakref_require?(node)
        def_node_matcher :weakref_require?, <<~PATTERN
          (send {nil? (const {nil? cbase} :Kernel)} :require (str "weakref"))
        PATTERN

        def on_const(node)
          return unless object_space_weak_map?(node) || weak_ref_const?(node) ||
                        bare_weak_map_inside_object_space?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end

        def on_send(node)
          return unless weakref_require?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end

        private

        # `WeakMap`/`WeakKeyMap` written bare, lexically inside `module ObjectSpace`. RuboCop
        # parses and never evaluates, so this fires on the source text regardless of whether the
        # constant would resolve at runtime.
        def bare_weak_map_inside_object_space?(node)
          return false unless node.namespace.nil? && WEAK_MAP_NAMES.include?(node.short_name)

          node.each_ancestor(:module).any? do |mod|
            mod.identifier.const_type? && mod.identifier.short_name == :ObjectSpace
          end
        end
      end
    end
  end
end
