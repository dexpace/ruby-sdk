# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Inside `module Dexpace::Async` and `module Dexpace::Serde`, a bare `Thread`, `Queue`,
      # `Mutex`, `SizedQueue`, `ConditionVariable` or `JSON` is a silent time bomb: it resolves to
      # Ruby's class until the adapter gem that defines `Dexpace::Async::Thread` or
      # `Dexpace::Serde::JSON` is required, and to that module afterwards.
      #
      # Verified on Ruby 3.2.11 and 4.0.6: before the adapter loads, a bare `Thread` inside
      # `module Dexpace; module Async` is `Thread`; after, it is `Dexpace::Async::Thread`, and
      # `Thread.new` raises `NoMethodError: undefined method 'new' for module
      # Dexpace::Async::Thread`. dexpace-core's own suite never requires that gem, so this is a bug
      # that cannot fail in the tree that contains it -- which is what a cop is for.
      #
      # Scoped by `Include:` in .rubocop.yml to gems/dexpace-core/lib/dexpace/{async,serde}/**/*.rb.
      #
      # The enclosing namespace is checked here rather than left to `Include:` in .rubocop.yml.
      # Phase 0's cop harness runs a bare Commissioner over a fixed path with a Config carrying
      # only TargetRubyVersion, so no `Include:` ever applies to a cop under test -- a cop that
      # relied on path scoping would flag its own accepted case and the suite would say so.
      # `Include:` stays in .rubocop.yml anyway, because it is what keeps the cop off the other
      # five gems during a real run.
      #
      # SHADOWED is one list for both watched namespaces rather than one list each, so a bare
      # `JSON` inside Dexpace::Async is flagged even though only Dexpace::Serde reopens JSON. Two
      # per-namespace lists would be a second rule to keep in step for no gain, and the false
      # positive costs one `::`.
      #
      # @example
      #   # bad -- inside module Dexpace; module Async
      #   Queue.new
      #
      #   # good
      #   ::Queue.new
      #
      #   # good -- a different namespace; nothing reopens Dexpace::Transport::Thread
      #   Thread.new
      class QualifiedCoreConstant < Base
        MSG = "Write `::%<name>s` here: a bare `%<name>s` inside %<namespace>s rebinds to the " \
              "adapter gem's constant once that gem is required."

        SHADOWED = %w[Thread Queue Mutex SizedQueue ConditionVariable JSON].freeze

        WATCHED = [%w[Dexpace Async], %w[Dexpace Serde]].freeze

        def on_const(node)
          return if node.namespace # already qualified: `A::Thread` or `::Thread`
          return unless SHADOWED.include?(node.short_name.to_s)

          namespace = watched_namespace(node)
          return if namespace.nil?

          add_offense(node, message: format(MSG, name: node.short_name, namespace: namespace))
        end

        private

        # @return [String, nil] the watched namespace this node is lexically inside, or nil
        def watched_namespace(node)
          path = lexical_path(node)
          watched = WATCHED.find { |segments| path.each_cons(segments.length).any?(segments) }
          watched&.join("::")
        end

        # Outermost-first, with a compact `module A::B` split into its segments, so that both
        # `module Dexpace; module Async` and `module Dexpace::Async` read the same. A
        # `class << self` is an sclass node, not a class node, so it contributes no segment.
        def lexical_path(node)
          node.each_ancestor(:module, :class)
            .map { |scope| scope.identifier.source }
            .reverse
            .flat_map { |name| name.split("::") }
        end
      end
    end
  end
end
