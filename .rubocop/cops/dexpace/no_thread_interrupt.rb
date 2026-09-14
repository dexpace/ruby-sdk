# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module RuboCop
  module Cop
    module Dexpace
      # Design §8.3, and CLAUDE.md's "Constraints that will bite". An asynchronous interrupt can
      # land on any bytecode instruction, including inside an `ensure` releasing a pooled
      # connection, so deadlines here are explicit values propagated to socket timeouts, never
      # ambient interrupts. Modelled on Airbnb/NoTimeout, and it shares that cop's limit: the
      # receiver is matched by name, so a Thread held in a variable named nothing like a thread
      # is missed. That is why the rule is also stated in CLAUDE.md and checked in review.
      #
      # `@thread&.kill` in a `close` is the ordinary spelling of the ban -- and exactly where the
      # interrupt lands inside an `ensure` -- so the safe-navigation form is an offence too, and
      # so is `threads.each(&:kill)`, the block-pass spelling with no receiver to match by name.
      class NoThreadInterrupt < Base
        MSG = "`%<offender>s` is banned repository-wide: an async interrupt can land on any " \
              "bytecode instruction, including inside an `ensure` releasing a pooled " \
              "connection. Propagate an explicit deadline instead (design §8.3)."
        INTERRUPTS = %i[raise kill terminate exit].freeze
        RESTRICT_ON_SEND = (INTERRUPTS + %i[timeout]).freeze
        THREADISH = /\A(::)?Thread\b|thread/i

        # @!method timeout_timeout?(node)
        def_node_matcher :timeout_timeout?, <<~PATTERN
          ({send csend} (const {nil? cbase} :Timeout) :timeout ...)
        PATTERN

        # @!method interrupt_block_pass?(node)
        def_node_matcher :interrupt_block_pass?, "(block_pass (sym {:kill :terminate :exit}))"

        def on_send(node)
          return unless timeout_timeout?(node) || thread_interrupt?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end
        alias on_csend on_send

        def on_block_pass(node)
          return unless interrupt_block_pass?(node)

          add_offense(node, message: format(MSG, offender: node.source))
        end

        private

        def thread_interrupt?(node)
          return false unless INTERRUPTS.include?(node.method_name)
          return false if node.receiver.nil? # a bare `raise` is ordinary Ruby

          THREADISH.match?(node.receiver.source)
        end
      end
    end
  end
end
