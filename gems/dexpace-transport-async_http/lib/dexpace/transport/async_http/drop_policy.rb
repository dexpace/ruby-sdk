# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # TRANSPORT-13 (SHOULD), and the OBS-19 header-drop policy phase 5b postponed to the first
      # adapter that drops a caller-set header rather than raising on it: how a TRANSPORT-12 drop
      # is logged, in one of three modes, with the per-name dedup mode case-insensitive and bounded
      # so an attacker synthesising distinct names cannot grow it without limit. A TRANSPORT-11
      # framing drop never goes through this policy and is always VERBOSE: three modes over a set
      # the caller controls would let an attacker suppress a WARNING by exhausting the bound.
      #
      # Not itself a Data.define value, although phase 5b's hand-forward reads that way: a Data is
      # frozen at the end of its #initialize, and this object's whole job is to grow a bounded
      # per-name table over its own lifetime. What IS frozen Data is the SNAPSHOT it holds in one
      # ivar and replaces wholesale under its own mutex on the write path, reading it without a
      # lock everywhere else -- concurrency-and-async/f414b864's shape, and phase 2's Registry's.
      class DropPolicy
        # The frozen table of folded names already warned about.
        Snapshot = ::Data.define(:seen)
        private_constant :Snapshot

        # TRANSPORT-13's bound: after this many distinct folded names the once-per-name mode stops
        # tracking and degrades to the quiet mode for every further name, rather than growing.
        MAX_TRACKED_NAMES = 64

        # Every drop at WARNING.
        EVERY = :every

        # The default: the first drop per distinct folded name at WARNING, the rest at VERBOSE.
        ONCE_PER_NAME = :once_per_name

        # Every drop at VERBOSE.
        QUIET = :quiet

        # The closed set of modes.
        MODES = [EVERY, ONCE_PER_NAME, QUIET].freeze

        private_class_method :new

        # The validating factory; a mode outside MODES is refused here rather than degraded.
        #
        # @param mode [Symbol] one of MODES
        # @return [DropPolicy]
        # @raise [Dexpace::InvalidArgumentError] for a mode outside MODES
        def self.build(mode: ONCE_PER_NAME)
          unless MODES.include?(mode)
            raise ::Dexpace::InvalidArgumentError,
                  "mode must be one of #{MODES.inspect}, got #{mode.inspect}"
          end

          new(mode: mode)
        end

        def initialize(mode:)
          @mode = mode
          @mutex = ::Thread::Mutex.new
          seen = {} #: Hash[String, bool]
          @snapshot = Snapshot.new(seen: seen.freeze)
        end

        # @return [Symbol] the mode this policy was built with
        attr_reader :mode

        # Logs one drop under the shared transport event, at the severity this policy's mode
        # picks for this name -- TRANSPORT-13's own conformance clause: "under once-per-header
        # assert the same name warns once then goes quiet, a different name warns once." Every
        # emission runs inside Instrumentation.contain, because OBS-20's "every log-emission site"
        # is not scoped to phase 5's own sites.
        #
        # @param logger [Dexpace::Instrumentation::Logger]
        # @param name [String] the header name as the caller spelled it
        # @param reason [String] why it was dropped
        # @return [nil]
        def report(logger, name, reason)
          severity = severity_for(name)
          event = ::Dexpace::Instrumentation::Events::TRANSPORT_HEADER_DROPPED
          ::Dexpace::Instrumentation.contain(logger, event: event) do
            logger.event(severity).event(event).field("header", name.to_s).field("reason", reason)
              .emit
          end
          nil
        end

        private

        def severity_for(name)
          case @mode
          when EVERY then ::Dexpace::Instrumentation::Severity::WARNING
          when QUIET then ::Dexpace::Instrumentation::Severity::VERBOSE
          else once_per_name_severity(name)
          end
        end

        def once_per_name_severity(name)
          if first_sighting?(name.to_s.downcase)
            ::Dexpace::Instrumentation::Severity::WARNING
          else
            ::Dexpace::Instrumentation::Severity::VERBOSE
          end
        end

        # Folded with `downcase` and no locale argument (HTTP-13). The mutex is held across the
        # snapshot swap and nothing else; the bound is checked before the table grows, so the
        # 65th distinct name is neither tracked nor warned about.
        def first_sighting?(folded)
          @mutex.synchronize do
            seen = @snapshot.seen
            next false if seen.key?(folded) || seen.size >= MAX_TRACKED_NAMES

            @snapshot = Snapshot.new(seen: seen.merge(folded => true).freeze)
            true
          end
        end
      end
    end
  end
end
