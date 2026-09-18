# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/seam_error"
require_relative "error/invalid_argument_error"
require_relative "suppressible"
require_relative "instrumentation/keys"
require_relative "instrumentation/logger"
require_relative "instrumentation/contain"

# Dexpace::Closeable and Dexpace.close_quietly live in one file: the helper is the contract's
# discard-path exit and has no meaning apart from it (module-organization/1828a984 counts
# constants, and this file defines one).
module Dexpace
  # The close contract, written down once because six requirements state it in six vocabularies --
  # SEAM-14, SEAM-25, HTTP-43, ASYNC-15..ASYNC-17, XCUT-13 and XCUT-22 -- and Ruby has no Closeable
  # interface and no try-with-resources to infer it from.
  #
  # Three properties, and each is here rather than in each implementation because each was
  # implemented differently at three sites in the reference build. (1) Close is idempotent, latched
  # rather than flag-checked: whoever flips the latch runs #release and everyone else returns.
  # (2) Ownership is a construction-time fact, not a close-time judgement -- a component takes a
  # resource through an entry point that either builds it or borrows it, and records which in a
  # frozen boolean. (3) Close never blocks on an interrupt-sensitive wait, which is free here
  # because this port delivers no interrupts (design §8.3).
  #
  # The latch mutex is created in #initialize_closeable rather than lazily, because a lazily
  # created mutex is itself the race it exists to prevent.
  module Closeable
    # Call from the including class's #initialize. `owned:` is SEAM-14's and XCUT-22's distinction:
    # false means the caller supplied the resource and the SDK must never release it.
    def initialize_closeable(owned: true)
      @dexpace_owned = owned ? true : false
      @dexpace_closed = false
      @dexpace_close_mutex = ::Thread::Mutex.new
      nil
    end

    # Whether #close will run #release: true for a resource this component built, false for one
    # the caller supplied.
    def owned?
      ensure_closeable_initialized
      @dexpace_owned
    end

    # Whether the latch has flipped, whatever ownership says: a borrowing wrapper is closed once
    # #close has been called even though the resource it borrowed is not.
    #
    # IO-38 (phase 3a, P3-6): the latch is read under the same Thread::Mutex that writes it, so a
    # close on one thread reliably invalidates a slice being read on another. Design §3.1 fixes
    # the mechanism -- "written and read through a Thread::Mutex rather than relying on the GVL,
    # so the guarantee survives JRuby and TruffleRuby" -- and phase 2's unsynchronised read relied
    # on exactly the GVL that sentence declines to rely on. Measured at ~40 ns per call on 3.2.11,
    # 3.4.10 and 4.0.6, paid once per public entry point and never per byte. No GVL-free
    # interpreter is in the matrix (3a's design, "Work Phase 3a Postpones"), so on every CI row
    # this read passes with or without the lock: the assertion that distinguishes them is the
    # fiber-held-mutex test in closeable_test.rb.
    def closed?
      ensure_closeable_initialized
      @dexpace_close_mutex.synchronize { @dexpace_closed }
    end

    # Idempotent and ownership-aware. The mutex is held across the flag flip and nothing else:
    # Ruby's Mutex is per-fiber-owned and non-reentrant, so holding it across a #release that may
    # suspend deadlocks two fibers of one thread. A #release that raises still leaves the latch
    # flipped, so no second release is attempted and the failure propagates exactly once.
    def close
      ensure_closeable_initialized
      first = @dexpace_close_mutex.synchronize do
        if @dexpace_closed
          false
        else
          @dexpace_closed = true
        end
      end
      return nil unless first
      return nil unless @dexpace_owned

      release
      nil
    end

    private

    # NotImplementedError is a ScriptError and not a StandardError, deliberately: an owning class
    # that forgot #release is a programmer error and must not be swallowed by an ordinary rescue
    # -- or by Dexpace.close_quietly's.
    def release
      raise NotImplementedError,
            "#{self.class} includes Dexpace::Closeable and must define a private #release"
    end

    def ensure_closeable_initialized
      return if defined?(@dexpace_close_mutex) && @dexpace_close_mutex

      raise Dexpace::SeamError,
            "#{self.class} includes Dexpace::Closeable but never called #initialize_closeable"
    end
  end

  # The single sanctioned exit for a close on a cleanup or discard path: null-safe (CFG-21's last
  # clause), tolerant of an object with no #close, and never raising over a primary failure.
  #
  # Design §3.7 gives the rescued error two disposal routes, and both now exist. With `onto:`
  # supplied, the rescued close failure lands on that error's suppressed trail through
  # Dexpace.attach_suppressed (phase 4b, Task 2); the carrier is Dexpace::Suppressible and not
  # Dexpace::Error, because the primary a caller hands in is whatever it is unwinding with
  # (P4-12). With `onto:` absent, the failure is emitted as an `http.instrumentation.close`
  # diagnostic through `logger:` -- §8.1's facade, the second route phase 2 postponed and phase 5b
  # supplies -- inside Instrumentation.contain, so a sink that raises cannot turn a cleanup into a
  # failure (OBS-20). There is no process-wide logger to reach for (a logger slot beside
  # Dexpace.configuration would be 5a's object), so the logger is a keyword defaulting to
  # Logger::NULL, under which the route emits nothing: every phase-2 call site is byte-for-byte
  # as it was, and a caller who wants the diagnostic passes a logger. One helper gains two
  # keywords and no second helper appears, which is what keeps §3.7's "two ways and never a third"
  # true. The two loud exceptions §3.7 names are honoured and do not come through here: an
  # explicit #close by a caller propagates, and a #release raising during the latched close above
  # propagates once. Only StandardError is rescued: a NotImplementedError from a class that forgot
  # #release is a programmer error, not a close failure, whatever `onto:` says.
  #
  # `onto:` is validated at ENTRY, outside the rescue region, and that placement is the decision:
  # attach_suppressed raises InvalidArgumentError for a non-Exception, and validating inside the
  # rescue would replace the close failure this method was passed to carry with a caller-mistake
  # error -- the one thing §3.7 promises close_quietly never does. So a bad `onto:` is refused
  # while the caller is still the only thing that has gone wrong, before the resource is touched.
  # A nil `onto:` is the documented no-attach default and is not a caller mistake.
  #
  # @param resource [#close, nil] whatever is being discarded
  # @param onto [Exception, nil] the primary failure a close failure must not mask
  # @param logger [Dexpace::Instrumentation::Logger] where an unattached close failure is
  #   reported; Logger::NULL, the default, reports nothing
  # @return [nil] always, so a caller cannot branch on a cleanup outcome
  # @raise [Dexpace::InvalidArgumentError] when `onto:` is neither nil nor an Exception
  def self.close_quietly(resource, onto: nil, logger: Instrumentation::Logger::NULL)
    unless onto.nil? || onto.is_a?(::Exception)
      raise InvalidArgumentError, "onto must be an Exception"
    end
    return nil if resource.nil?
    return nil unless resource.respond_to?(:close)

    begin
      resource.close
    rescue ::StandardError => error
      if onto.nil?
        # The second disposal route: a diagnostic, itself contained (OBS-20).
        Instrumentation.diagnostic(logger, event: Instrumentation::Events::INSTRUMENTATION_CLOSE,
                                           cause: error,)
      else
        # The first disposal route, phase 4b's trail.
        attach_suppressed(onto, error)
      end
    end
    nil
  end
end
