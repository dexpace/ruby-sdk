# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../cancellation"
require_relative "../hooks"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Cancellation
    # The write side of a cancellation, handed only to whoever is entitled to cancel -- the Ruby
    # answer to a language with no way to hide a mutator. A consumer holding the token cannot
    # cancel someone else's operation.
    #
    # State is one frozen Data snapshot swapped under a Thread::Mutex held across the swap and
    # nothing else; the hooks run outside it. The snapshot is a private_constant, so it does not
    # include Dexpace::Model and has no .build: phase 1's construction rule is about a public
    # constructor, and this has none (design P2-9).
    class Source
      State = ::Data.define(:cancelled, :reason, :cancelled_at)
      private_constant :State

      def initialize
        @mutex = ::Thread::Mutex.new
        @state = State.new(cancelled: false, reason: nil, cancelled_at: nil)
        @hooks = [] #: Array[^(untyped) -> void]
        @token = Cancellation.over(self)
      end

      # @return [Dexpace::Cancellation] the read side to hand to a transport
      attr_reader :token

      # Whether #cancel has been called.
      def cancelled? = @state.cancelled

      # The reason the first #cancel supplied, or nil.
      def reason = @state.reason

      # The monotonic nanosecond stamp taken when this source was cancelled, or nil. Public because
      # a composed token orders its sources by it to find the one that cancelled first in time,
      # which is what lets a token subscribe to nothing at construction.
      def cancelled_at = @state.cancelled_at

      # The state is published inside the lock and the hooks run outside it, so a handler that
      # raises can never leave the source uncancelled. The notification goes through Hooks.notify
      # rather than a bare `hooks.each`: one raising handler in a bare each drops every
      # later-registered handler, which is the "a second waiter on one token blocks forever"
      # SEAM-18 failure arriving from the write side -- verified on all three interpreters.
      #
      # @return [Boolean] true for the call that actually cancelled, false for every later one
      def cancel(reason = nil) # rubocop:disable Naming/PredicateMethod -- a command reporting whether it took effect, not a query; the design fixes the name
        at = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        hooks = @mutex.synchronize do
          if @state.cancelled
            nil
          else
            @state = State.new(cancelled: true, reason: reason, cancelled_at: at)
            taken = @hooks
            @hooks = []
            taken
          end
        end
        return false if hooks.nil?

        Hooks.notify(hooks, reason)
        true
      end

      # Registers a hook, or runs it immediately when the source has already cancelled.
      #
      # @return [self]
      def on_cancel(&block)
        raise Dexpace::InvalidArgumentError, "on_cancel requires a block" unless block

        settled = @mutex.synchronize do
          if @state.cancelled
            @state
          else
            @hooks << block
            nil
          end
        end
        yield settled.reason if settled
        self
      end

      # Withdraws a hook a token registered, so a bounded wait retains nothing on an unbounded
      # source. Called by Cancellation::Subscription#detach and by nothing else. Idempotent, and a
      # no-op once #cancel has taken the list. Array#delete compares with ==, which for a Proc is
      # object identity, so one registration is removed and an identical-looking one is not.
      #
      # @return [self]
      def off_cancel(hook)
        @mutex.synchronize { @hooks.delete(hook) }
        self
      end
    end
  end
end
