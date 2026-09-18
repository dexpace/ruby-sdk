# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../clock"
require_relative "../config"
require_relative "../configuration"
require_relative "../error/invalid_argument_error"
require_relative "policy"

module Dexpace
  module Resilience
    # RECOV-34 and RETRY-12: the ONE retry configuration, a frozen Data validated and defensively
    # copied at construction, that both stacks build from identical defaults -- RECOV-30's "the
    # SAME default schedule so the two stacks cannot drift apart" made an object rather than a
    # promise, because there is no second type to type a base delay into. Every default is
    # Policy's constant, read here and re-typed nowhere.
    #
    # `total_timeout` is carried for both stacks and read by one: RecoveryRetry applies it through
    # Policy.budget_remaining and RetryStep/AsyncRetryStep never read the member at all, which is
    # RETRY-28's prohibition kept structural (R6). `pacing_header_order` is nil by default and each
    # driver substitutes Policy::DEFAULT_PACING_HEADER_ORDER for nil, so RETRY-21's split
    # precedence -- fixed on the recovery stack, caller-configurable on the stage stack -- reads
    # from one member. `random` defaults to the ::Random CLASS, whose .rand is the process
    # generator CRuby already makes safe to share, rather than to a fresh instance every settings
    # object would then share unsynchronised across threads (RETRY-42's caveat, stated rather
    # than hidden); a seeded ::Random.new is what a test passes. `clock` is 5a's seam.
    #
    # `max_retries` is the STAGE vocabulary (excluding the initial send) and the recovery stack's
    # max_attempts is always max_retries + 1 (RETRY-14, P6-6). When a caller passes none, .build
    # reads 5a's Configuration::Keys::MAX_RETRY_ATTEMPTS off the process-wide slot -- this class is
    # that key's first and only reader -- and falls back to Policy::DEFAULT_MAX_RETRIES; the read
    # happens ONCE, at build, so a settings object is a snapshot and never re-consults the slot.
    class RetrySettings < Data.define(
      :initial_delay, :multiplier, :max_delay, :jitter, :max_retries, :total_timeout,
      :retryable_statuses, :pacing_header_order, :random, :clock,
    )
      include Dexpace::Model

      private_class_method :new

      # The absent-argument sentinel for max_retries: what lets "the caller passed nothing" be told
      # apart from "the caller passed the default", so the configured key is consulted only in the
      # first case and an explicit argument -- including one #with routes back through .build --
      # always wins. Private, and never a member's value.
      UNSET = ::Object.new.freeze
      private_constant :UNSET

      # The validating factory. Every keyword defaults to the shared policy constant.
      #
      # @param initial_delay [Numeric] seconds, non-negative
      # @param multiplier [Numeric] >= 1.0
      # @param max_delay [Numeric] seconds, non-negative
      # @param jitter [Numeric] in [0.0, 1.0]
      # @param max_retries [Integer] retries after the initial send, >= 0; the configured
      #   MAX_RETRY_ATTEMPTS, else Policy::DEFAULT_MAX_RETRIES, when omitted
      # @param total_timeout [Numeric] seconds; 0 disables the recovery stack's budget
      # @param retryable_statuses [Enumerable<Integer>] XCUT-7's configured set, copied
      # @param pacing_header_order [Array<String>, nil] RETRY-21's order, copied; nil for the
      #   shared default
      # @param random [#rand] the generator the jitter draws from
      # @param clock [Dexpace::_Clock] the seam every wait and every elapsed reading goes through
      # @return [RetrySettings] frozen
      # @raise [Dexpace::InvalidArgumentError] naming the member, on any invalid value
      def self.build(initial_delay: Policy::DEFAULT_INITIAL_DELAY,
                     multiplier: Policy::DEFAULT_MULTIPLIER, max_delay: Policy::DEFAULT_MAX_DELAY,
                     jitter: Policy::DEFAULT_JITTER, max_retries: UNSET, total_timeout: 0,
                     retryable_statuses: Policy::DEFAULT_RETRYABLE_STATUSES,
                     pacing_header_order: nil, random: ::Random, clock: Clock::SYSTEM)
        new(
          initial_delay: initial_delay, multiplier: multiplier, max_delay: max_delay,
          jitter: jitter, max_retries: resolve_max_retries(max_retries),
          total_timeout: total_timeout, retryable_statuses: retryable_statuses,
          pacing_header_order: pacing_header_order, random: random, clock: clock,
        )
      end

      # RETRY-12 / P6-6: the configured key, read once, only when nothing was passed.
      def self.resolve_max_retries(max_retries)
        return max_retries unless UNSET.equal?(max_retries)

        Dexpace.configuration.integer(Configuration::Keys::MAX_RETRY_ATTEMPTS,
                                      default: Policy::DEFAULT_MAX_RETRIES,) ||
          Policy::DEFAULT_MAX_RETRIES
      end
      private_class_method :resolve_max_retries

      # RECOV-34, clause by clause, each failure naming its member (SEAM-29); the collections
      # are copied and deep-frozen here, once, through Model.own.
      def initialize(initial_delay:, multiplier:, max_delay:, jitter:, max_retries:,
                     total_timeout:, retryable_statuses:, pacing_header_order:, random:, clock:)
        Model.required!("random", random)
        Model.required!("clock", clock)
        super(
          initial_delay: duration!("initial_delay", initial_delay),
          multiplier: multiplier!(multiplier), max_delay: duration!("max_delay", max_delay),
          jitter: jitter!(jitter), max_retries: max_retries!(max_retries),
          total_timeout: duration!("total_timeout", total_timeout),
          retryable_statuses: statuses!(retryable_statuses),
          pacing_header_order: order!(pacing_header_order), random: random, clock: clock,
        )
      end

      # The keyword hash Policy.backoff_delay takes, so neither driver spells the five members
      # out by hand (RETRY-13).
      #
      # @return [Hash]
      def backoff_arguments
        { initial_delay: initial_delay, multiplier: multiplier, max_delay: max_delay,
          jitter: jitter, random: random, }
      end

      # RETRY-21: the order the drivers walk -- the caller's, or the shared default.
      #
      # @return [Array<String>] frozen
      def header_order
        pacing_header_order || Policy::DEFAULT_PACING_HEADER_ORDER
      end

      private

      # Non-negative, finite, and representable within the ~292-year nanosecond ceiling
      # (design §10.18); returned as a Float so the arithmetic downstream is uniform.
      def duration!(name, value)
        Model.required!(name, value)
        seconds = numeric!(name, value)
        if seconds.negative? || !seconds.finite?
          raise InvalidArgumentError, "#{name} must be a finite non-negative number of seconds"
        end
        if seconds * 1_000_000_000 > Policy::MAX_DURATION_NANOSECONDS
          raise InvalidArgumentError, "#{name} exceeds the representable ceiling (RECOV-34)"
        end

        seconds
      end

      def multiplier!(value)
        Model.required!("multiplier", value)
        factor = numeric!("multiplier", value)
        raise InvalidArgumentError, "multiplier must be >= 1.0 (RECOV-34)" if factor < 1.0
        raise InvalidArgumentError, "multiplier must be finite" unless factor.finite?

        factor
      end

      def jitter!(value)
        Model.required!("jitter", value)
        fraction = numeric!("jitter", value)
        return fraction if fraction.between?(0.0, 1.0)

        raise InvalidArgumentError, "jitter must lie within [0.0, 1.0] (RECOV-34)"
      end

      def max_retries!(value)
        Model.required!("max_retries", value)
        return value if value.is_a?(::Integer) && !value.negative?

        raise InvalidArgumentError, "max_retries must be a non-negative Integer (RECOV-34)"
      end

      def statuses!(value)
        Model.required!("retryable_statuses", value)
        unless value.respond_to?(:each) && value.all?(::Integer)
          raise InvalidArgumentError, "retryable_statuses must be a collection of Integers"
        end

        Model.own(::Set.new(value))
      end

      def order!(value)
        return nil if value.nil?
        unless value.is_a?(::Array) && value.all?(::String)
          raise InvalidArgumentError, "pacing_header_order must be an Array of header names"
        end

        Model.own(value.dup)
      end

      def numeric!(name, value)
        unless value.is_a?(::Numeric)
          raise InvalidArgumentError, "#{name} must be a number, got #{value.class}"
        end

        number = value #: untyped
        number.to_f
      end
    end
  end
end
