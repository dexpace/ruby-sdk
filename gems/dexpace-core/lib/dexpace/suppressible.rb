# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# This file requires nothing, and that is load-bearing rather than an omission. `error.rb`
# requires this file so `include Dexpace::Suppressible` resolves, and
# `error/invalid_argument_error.rb` requires `error.rb`. A `require_relative` back to the
# argument error from here closes that cycle: `error.rb` would re-enter as a no-op and run
# `include Dexpace::Suppressible` before this file's body has, raising NameError at load in
# every consumer at once. `lib/dexpace.rb` loads the whole tree, so
# `Dexpace::InvalidArgumentError` is defined long before `attach_suppressed` is first called.
#
# Dexpace::Suppressible and its two module functions live in one file, on phase 2's precedent
# for Dexpace::Closeable and Dexpace.close_quietly: the helper is the contract's only writer and
# has no meaning apart from it (module-organization/1828a984 counts constants, and this file
# defines one).
module Dexpace
  # The suppressed-exception trail: the secondary failures an error accumulated while it was
  # being handled -- a close that failed while unwinding (RECOV-12), a later hook that raised
  # (Hooks.notify), the earlier attempts behind a terminal retry failure (RETRY-34) -- carried on
  # the error itself, the way Java's `Throwable#getSuppressed` does and Ruby's `#cause` does not.
  #
  # A separate module rather than a method on Dexpace::Error, and the split is forced (P4-12):
  # every primary the helper is handed is a CALLER's exception -- whatever a step, a hook or a
  # `#close` raised -- so the trail must be attachable to an object whose class core does not
  # control, and `Object#extend` is Ruby's only mechanism for that. `rescue M` matches a module
  # reached through a singleton class (verified on 3.2.11, 3.4.10 and 4.0.6), so extending a
  # third-party IOError with the rescue root would make `rescue Dexpace::Error` catch errors the
  # SDK never raised, the one promise phase 1's P1-2 made. Dexpace::Error includes this module,
  # so every SDK error carries the trail by inclusion; Dexpace.attach_suppressed extends anything
  # else. The cost, stated because it is observable: `rescue Dexpace::Suppressible` is a second,
  # broader rescue point beside `rescue Dexpace::Error`, and it also matches an extended
  # third-party error (P4-15).
  #
  # There is no writer here, public or private. The only way onto the trail is
  # Dexpace.attach_suppressed, which is what keeps RETRY-34's skip-self guard in one place and
  # unavoidable. The state is one namespaced instance variable, `@dexpace_suppressed`, following
  # Closeable's `@dexpace_closed`: under `extend` it lands on a caller's exception object, so the
  # name has to be one no application would pick.
  #
  # No mutex, and the reason is the single-writer discipline at every call site rather than any
  # measurement: RECOV-12 unwinds on one thread, Hooks.notify drains one list on one thread,
  # RETRY-34 attaches on one. A concurrent read-modify-write on ONE error's trail does lose
  # writes -- measured on 3.2.11, and not on 3.4.10 or 4.0.6, which is scheduling and not
  # safety -- and a per-exception lock on a caller's object is not available in any case. Core
  # makes no thread-safety claim for concurrent attaches to one error object.
  module Suppressible
    # The trail an error carries before its first attach: one shared frozen array, so the empty
    # case allocates nothing and a caller holding it holds a stable snapshot like any other.
    empty = [] #: Array[::Exception]
    EMPTY = empty.freeze
    private_constant :EMPTY

    # The frozen trail, `[]` when empty. Never a mutable internal array under another name:
    # every attach REPLACES the frozen array (P4-14), so "frozen once populated" is true at every
    # moment, a handle a caller took earlier stays a stable snapshot of that moment, and no
    # per-read `dup` is needed. Reading never writes an instance variable: an SDK error may be
    # frozen (a constant, a shared sentinel), and a reader that memoised into an ivar would turn
    # every read of a frozen error's trail into a FrozenError.
    #
    # @return [Array<Exception>] frozen, oldest first
    def suppressed
      defined?(@dexpace_suppressed) ? @dexpace_suppressed : EMPTY
    end

    # Ruby's own rendering, then the trail: one header naming the count and one indented line
    # per suppressed error naming its class and message. `super` is mandatory rather than
    # decorative -- Ruby composes a NoMethodError's did_you_mean suggestion and a NameError's
    # error highlight inside its own #detailed_message, and this override appends to that
    # rather than replacing it (verified on 3.2.11, 3.4.10 and 4.0.6).
    #
    # Only #detailed_message is overridden, never #full_message: Ruby's default
    # uncaught-exception printer calls #detailed_message and not a Ruby-level #full_message, and
    # Exception#full_message itself calls #detailed_message, so this one override reaches both
    # paths and a second would be a second copy of the rendering with two ways to drift. A logger
    # that formats an exception itself sees neither, which is what Dexpace.suppressed is for.
    #
    # The keywords Ruby passes -- `highlight:` today, and whatever a later Ruby adds -- arrive as
    # one positional Hash and are forwarded to `super` unnamed, so no future keyword can make
    # this signature wrong. That is Model#with's spelling: Ruby passes keywords to a method that
    # declares none as one positional Hash on every Ruby in the supported range, and a `**` rest
    # parameter is what Dexpace/NoKeywordSplat forbids on a public library method.
    #
    # @param options [Hash, nil] the keywords Ruby's printer or Exception#full_message passed
    # @return [String]
    def detailed_message(options = nil)
      base = options.nil? ? super() : super(**options)
      trail = suppressed
      return base if trail.empty?

      lines = [base, "Suppressed exceptions (#{trail.size}):"]
      trail.each_with_index do |error, index|
        lines << "  (#{index + 1}) #{error.class}: #{error.message}"
      end
      lines.join("\n")
    end
  end

  # Attaches `secondary` to `primary`'s suppressed trail and returns `primary`, so it composes
  # inside a `rescue` or an `ensure` without a temporary. Four rules, in the order they apply:
  #
  # 1. Either argument not being an Exception is a caller mistake and raises
  #    Dexpace::InvalidArgumentError -- unreachable from core's own call sites, which all pass a
  #    rescued object.
  # 2. `primary.equal?(secondary)` attaches nothing: RETRY-34's skip-self guard, by identity and
  #    never by `==`, because Exception#== is structural (class, message, backtrace) and a
  #    DIFFERENT error that happened to match would otherwise be silently dropped.
  # 3. A primary that is not already Suppressible is extended with it (P4-13): a visible change
  #    to an object core did not create, which is exactly what the requirement asks for. Extend
  #    on an already-extended object is a no-op.
  # 4. A frozen primary is left untouched and returned unchanged. `extend` and the instance
  #    variable write both raise FrozenError on a frozen exception, and a helper that raised
  #    while attaching a CLOSE error would replace the primary with a FrozenError -- the masking
  #    RECOV-12 exists to prevent. The one-class deliberate swallow is the whole of that rule; the
  #    trail is simply not recorded, which the caller can observe through Dexpace.suppressed.
  #
  # @param primary [Exception] the error being surfaced
  # @param secondary [Exception] the error that must not mask it
  # @return [Exception] `primary`, always
  # @raise [Dexpace::InvalidArgumentError] when either argument is not an Exception
  def self.attach_suppressed(primary, secondary)
    raise InvalidArgumentError, "primary must be an Exception" unless primary.is_a?(::Exception)
    raise InvalidArgumentError, "secondary must be an Exception" unless secondary.is_a?(::Exception)
    return primary if primary.equal?(secondary)

    begin
      primary.extend(Suppressible) unless primary.is_a?(Suppressible)
      primary.instance_variable_set(:@dexpace_suppressed, [*suppressed(primary), secondary].freeze)
    rescue ::FrozenError
      # Rule 4: attaching to a frozen primary is a documented no-op rather than a raise, because
      # this helper runs on cleanup paths where raising would mask the primary (RECOV-12).
      primary
    end
    primary
  end

  # The frozen trail of anything: `[]` for an error that carries none, and for an object that is
  # not Suppressible at all. Public because RECOV-10 rethrows a caller's error unchanged, so a
  # consumer reading a trail off a surfaced error cannot know whether it is Suppressible without
  # writing `respond_to?` at every read site -- and because a logger that formats an exception
  # itself, rather than calling #full_message, sees no #detailed_message override and this is
  # the only route by which it gets the trail (P4-15).
  #
  # @param error [Exception] any error
  # @return [Array<Exception>] frozen, oldest first, possibly empty
  def self.suppressed(error)
    return error.suppressed if error.is_a?(Suppressible)

    empty = [] #: Array[::Exception]
    empty.freeze
  end
end
