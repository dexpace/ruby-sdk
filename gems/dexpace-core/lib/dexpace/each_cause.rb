# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/invalid_argument_error"

# Dexpace.each_cause lives in its own file rather than beside Dexpace::Suppressible: it serves
# XCUT-9 and not the trail, and its only relationship to the trail is that a trail is walked with
# it (module-organization/1828a984 counts constants; this file adds a function and no constant).
module Dexpace
  # XCUT-9: the one cause walk in the port. Every classification that inspects an error's
  # #cause chain -- "is this retryable", "is this a cancellation", "is there a protocol error
  # under this wrapper" -- goes through it, and none walks #cause by hand; phase 9's XCUT-9 audit
  # is what checks that repository-wide, since core can only guarantee its own callers.
  #
  # Yields the error itself first, then each #cause transitively (P4-16): every consumer is a
  # classification that has to inspect the error before its causes, and a walk that skipped the
  # head would put the same two-line preamble at every call site. The name reads the other way,
  # which is why this is stated.
  #
  # Cycle-safe by reference identity. Visited objects are tracked in a Hash built with
  # #compare_by_identity, never an Array and never a Set: Exception#== is structural (class,
  # message, backtrace), so an Array's #include? truncates a legitimate chain of two distinct
  # errors carrying identical fields to one; and a Set uses #eql?/#hash, which a caller-supplied
  # error class can override structurally to the same effect. Only identity comparison is immune
  # to both, and the errors walked here are caller-supplied by construction (verified on 3.2.11,
  # 3.4.10 and 4.0.6; docs/knowledge/notes/error-handling.md). The cycle itself is reachable only
  # through a caller-defined #cause override -- Ruby refuses `raise y, cause: x` on a linked pair
  # -- which is the same source, so the guard is live rather than theoretical.
  #
  # #cause is called on caller-supplied objects and may raise or lie. A #cause that raises a
  # StandardError ends the chain, and so does one that returns something other than an
  # Exception: a classification must never be the thing that fails, and must never be handed a
  # String as though it were a cause.
  #
  # With no block, returns an Enumerator -- safe here specifically because the walk acquires no
  # resource, so an abandoned enumerator leaks nothing an `ensure` would have released (design
  # §7.1) -- which is what lets a classification write `each_cause(error).any? { … }`.
  #
  # @param error [Exception] the error to walk
  # @yieldparam cause [Exception] the error, then each cause, nearest first
  # @return [nil] with a block; an Enumerator without one
  # @raise [Dexpace::InvalidArgumentError] when `error` is not an Exception
  def self.each_cause(error, &block)
    raise InvalidArgumentError, "error must be an Exception" unless error.is_a?(::Exception)
    return to_enum(:each_cause, error) unless block

    visited = {} #: Hash[::Exception, true]
    visited.compare_by_identity
    # @type var current: ::Exception?
    current = error
    until current.nil? || visited.key?(current)
      visited[current] = true
      yield current
      current = next_cause(current)
    end
    nil
  end

  # The one place #cause is called on a caller's object. A raise ends the chain; so does a
  # non-Exception. Only StandardError is rescued: a NotImplementedError from a caller's #cause is
  # a programmer error and propagates, exactly as everywhere else in core.
  def self.next_cause(error)
    cause = error.cause
    cause.is_a?(::Exception) ? cause : nil
  rescue ::StandardError
    nil
  end
  private_class_method :next_cause
end
