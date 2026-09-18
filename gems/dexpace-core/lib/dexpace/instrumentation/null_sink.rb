# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # The class behind NULL_SINK: every level disabled, every write discarded, the block never
    # evaluated. It IS the sink duck type, written out once because nothing else in core writes
    # it down: anything responding to #debug/#info/#warn/#error, each taking a message or a
    # block, and #debug?/#info?/#warn?/#error?. That is a structural subset of the stdlib
    # Logger's surface, so a stdlib Logger, a Rails logger or SemanticLogger drops in with no
    # adapter -- and core still never requires `logger`, which becomes a bundled gem in Ruby 4.0
    # (design §2.4, boundary 1). Frozen, stateless, safe from any thread.
    class NullSink
      # rubocop:disable Lint/UnusedMethodArgument -- the message is the documented protocol; a
      # discarding sink has nothing to do with it, and the block is deliberately never yielded.
      #
      # Each writer DECLARES the block it discards, as an anonymous `&`. A method that neither
      # declares nor uses a block warns "the block passed to ... may be ignored" under -w on Ruby
      # 3.4 and later -- suppressed process-wide once any same-named block-taking method has
      # been compiled, which is why a whole-suite run cannot see it and a lone `ruby -w` on the
      # sink's own test can. An anonymous `&` that is never referenced materialises no Proc
      # (measured: 0.0 objects per call on 3.2.11, 3.3.12, 3.4.10 and 4.0.6), so OBS-1's
      # zero-allocation write still holds; `block_given?` does not count as use.

      # Discards the message; never evaluates the block.
      #
      # @param message [Object, nil] the message, or nil under the block form
      # @return [nil]
      def debug(message = nil, &)
        nil
      end

      # Discards the message; never evaluates the block.
      #
      # @param message [Object, nil] the message, or nil under the block form
      # @return [nil]
      def info(message = nil, &)
        nil
      end

      # Discards the message; never evaluates the block.
      #
      # @param message [Object, nil] the message, or nil under the block form
      # @return [nil]
      def warn(message = nil, &)
        nil
      end

      # Discards the message; never evaluates the block.
      #
      # @param message [Object, nil] the message, or nil under the block form
      # @return [nil]
      def error(message = nil, &)
        nil
      end
      # rubocop:enable Lint/UnusedMethodArgument

      # Always disabled.
      #
      # @return [false]
      def debug?
        false
      end

      # Always disabled.
      #
      # @return [false]
      def info?
        false
      end

      # Always disabled.
      #
      # @return [false]
      def warn?
        false
      end

      # Always disabled.
      #
      # @return [false]
      def error?
        false
      end
    end
    private_constant :NullSink

    # OBS-1's default output: the one shared, frozen sink every level reads as disabled on, so a
    # Logger built over it hands back Event::INERT for every severity. Public for the reason
    # NO_SPAN is -- a conformance assertion names it by a qualified reference -- while its class
    # stays private. Named NULL_SINK and not §8.1's NullLogger (P5-19): the facade itself is
    # Logger, and a second Logger-shaped name in one namespace is the confusion 5a avoided for
    # Sources::ENV.
    NULL_SINK = NullSink.new.freeze
  end
end
