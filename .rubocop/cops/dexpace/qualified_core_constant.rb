# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Inside `module Dexpace`, anywhere, a bare `Thread`, `Queue`, `Mutex`, `SizedQueue`,
      # `ConditionVariable`, `JSON` or `IO` is a silent time bomb: it resolves to Ruby's class
      # until the `Dexpace::` constant that shadows it is defined, and to that constant
      # afterwards.
      #
      # Phase 2 verified the adapter-gem half on 3.2.11 and 4.0.6: a bare `Thread` inside
      # `module Dexpace; module Async` is `Thread` before `dexpace-async-thread` is required and
      # `Dexpace::Async::Thread` after, and core's own suite never requires that gem.
      #
      # Phase 3a adds `IO`, and it is worse, because `Dexpace::IO` is defined by CORE. Verified on
      # 3.2.11, 3.4.10 and 4.0.6: inside `module Dexpace`, `x.is_a?(IO)` and `IO === x` are
      # silently `false` for a real `::IO`, and a `case/when IO` falls through -- while a bare
      # `IO.pipe` is a loud NoMethodError. The silent case is exactly the shape design §3.1 reaches
      # for, and `Response#body_string`, which phase 3b adds under lib/dexpace/http/, is the
      # counter-example that forbids scoping this rule to lib/dexpace/io/**.
      #
      # The standing rule, for every later phase: a constant joins SHADOWED in the same change
      # that creates the `Dexpace::` constant which shadows it -- never earlier, never later.
      # `File`, `StringIO` and `Tempfile` are deliberately absent: no `Dexpace::` constant of those
      # names exists, a bare `File` inside `module Dexpace` resolves to `::File` (verified), and a
      # rule guarding nothing only flags correct code.
      #
      # Scoped by `Include:` in .rubocop.yml to gems/*/lib/**/*.rb -- every gem, because an
      # adapter gem also writes inside `module Dexpace`. test/** is deliberately left out: a test
      # file's classes are top level, not inside `module Dexpace`, so the lexical check below
      # would find nothing there.
      #
      # The enclosing namespace is checked here rather than left to `Include:`. Phase 0's cop
      # harness runs a bare Commissioner over a fixed path with a Config carrying only
      # TargetRubyVersion, so no `Include:` ever applies to a cop under test -- a cop that relied
      # on path scoping would flag its own accepted case and the suite would say so.
      #
      # @example
      #   # bad -- inside module Dexpace
      #   IO.pipe
      #
      #   # good
      #   ::IO.pipe
      #
      #   # good -- a different namespace; nothing named Elsewhere::IO exists
      #   IO.pipe
      class QualifiedCoreConstant < Base
        MSG = "Write `::%<name>s` here: a bare `%<name>s` inside %<namespace>s resolves to the " \
              "shadowing `Dexpace::` constant instead of Ruby's."

        SHADOWED = %w[Thread Queue Mutex SizedQueue ConditionVariable JSON IO].freeze

        # One segment, which subsumes phase 2's two: the rule is now "inside `module Dexpace`,
        # anywhere". Phase 2 deliberately kept ONE SHADOWED list for both namespaces rather than
        # one list each, and widening the watch rather than adding a per-constant scope keeps that
        # decision intact. The cost is one `::` on every `::Thread::Mutex` core already writes in
        # that form.
        WATCHED = [%w[Dexpace]].freeze

        def on_const(node)
          return if node.namespace # already qualified: `A::IO` or `::IO`
          return if definition_name?(node)
          return unless SHADOWED.include?(node.short_name.to_s)

          namespace = watched_namespace(node)
          return if namespace.nil?

          add_offense(node, message: format(MSG, name: node.short_name, namespace: namespace))
        end

        private

        # `module Dexpace; module IO` DECLARES the shadowing constant; it does not refer to Ruby's.
        # Without this, the cop flags lib/dexpace/io.rb -- the very file that creates the hazard
        # the rule exists to guard. Phase 2 never met this because no file declares
        # `module Dexpace::Async::Thread`.
        def definition_name?(node)
          parent = node.parent
          return false if parent.nil?
          return false unless parent.module_type? || parent.class_type?

          parent.identifier.equal?(node)
        end

        # @return [String, nil] the watched namespace this node is lexically inside, or nil
        def watched_namespace(node)
          path = lexical_path(node)
          watched = WATCHED.find { |segments| path.each_cons(segments.length).any?(segments) }
          watched&.join("::")
        end

        # Outermost-first, with a compact `module A::B` split into its segments, so that both
        # `module Dexpace; module IO` and `module Dexpace::IO` read the same. A
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
