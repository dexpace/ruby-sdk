# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"

require_relative "../closeable"
require_relative "../error/invalid_argument_error"
require_relative "../model"
require_relative "../http/method"
require_relative "../http/url"
require_relative "../instrumentation/logger"
require_relative "../pipeline/stages"
require_relative "../registry"
require_relative "chain"
require_relative "condition_snapshot"
require_relative "emitter"
require_relative "events"
require_relative "location"
require_relative "origin"
require_relative "reissue"

module Dexpace
  # The redirect layer (chapter 10, design §6.2): the synchronous redirect pillar step, the
  # condition snapshot a redirect predicate receives, the layer's event and key vocabulary, and
  # REDIR-15's error. Synchronous only -- the async pipeline follows no redirects (REDIR-25,
  # PIPE-32), which is why AsyncPipeline.standard takes `redirect: :unsupported` and no
  # Redirect::AsyncStep exists.
  module Redirect
    # The synchronous redirect pillar step at Stages::REDIRECT (order 200): one iterative
    # follower (REDIR-23) that forks a fresh Cursor for EVERY hop it drives, the first included,
    # and never calls its own cursor's #call (pipeline/86343352, P4-39) -- the fork is where the
    # cross-origin marker is written, so a first drive on the un-forked handle would have no
    # slot to write and hop 1 could publish nothing.
    #
    # Per hop: the response's status is classified (REDIR-1, REDIR-2) and a non-redirect status
    # returns before anything is allocated (REDIR-21's fast path); a recognized 3xx ALWAYS
    # allocates the ConditionSnapshot and consults a configured predicate, even with no usable
    # Location (REDIR-21's NOTE); the Location is resolved against the CURRENT hop through
    # URI::RFC3986_PARSER, screened, userinfo-stripped and frozen, once (REDIR-12, REDIR-13,
    # REDIR-14, REDIR-18, REDIR-19; R7); the decision is the predicate's alone when one is
    # configured (REDIR-20) and otherwise the built-in one -- the loop check (REDIR-16), the 303
    # opt-in (REDIR-5) or the ORIGINAL request's method against the allowed set (REDIR-3,
    # REDIR-4); REDIR-17's cap is a hard ceiling applied OVER that answer, never in place of
    # consulting it (R9, P6-91); the follow-up is built -- the downgrade check (REDIR-15), the
    # unconditional Authorization strip (REDIR-7), Cookie and Proxy-Authorization stripped on a
    # cross-origin hop only (REDIR-9, REDIR-10), the 303 GET rebuild (REDIR-5), the replayable-
    # body gate (REDIR-6) -- inside a frame that closes the current response before any raise
    # propagates (REDIR-22b); then the current response is closed BEFORE the next fork goes out
    # (REDIR-22a, PIPE-40), the hop is emitted (REDIR-28), and the loop goes round. Every
    # "return current" outcome hands the response back OPEN (REDIR-22c).
    #
    # The cross-origin marker is cursor state and never a header (design §10.15; spec-forced
    # boundary 2): `cursor.fork(state: { cross_origin: bool })` on every drive, `false` on the
    # seed's own and on a same-origin hop, `true` on a cross-origin one, judged against the SEED
    # origin and never the previous hop's (REDIR-8, REDIR-11, REDIR-24). Only this pillar's fork
    # can write the REDIRECT slot the AUTH step reads (4c's assertion 4), so a server-supplied
    # Location cannot forge it and nothing on the request needs stripping.
    #
    # Built through .build with .new private, frozen, holding six values and no per-request
    # state (PIPE-11): the seed origin, the visited set and the count are locals of one #call,
    # carried in a private Chain; the re-issue rules are the private Reissue and the records the
    # private Emitter, so this class reads as the follower alone. `logger:` is the step's own
    # keyword (R8); the Cursor's context bundle (6a's widening) carries a span tracer factory and
    # trace ids, not a logger, and is consumed here not at all. A few lines over the class-length
    # default, and deliberately one class: the six keywords' validation, the loop and its decision
    # are the follower, and the three concerns that could be split -- the re-issue rules, the
    # records and the per-call state -- already are (the recorded exception .rubocop.yml's metric
    # note asks for).
    class Step # rubocop:disable Metrics/ClassLength -- the follower and its validation, see above
      # REDIR-3, REDIR-4: the default allowed-method set -- exactly {GET, HEAD}, and NOT
      # Dexpace::Method::IDEMPOTENT, whose five members govern RETRY's re-sendability and would
      # silently widen redirect following to OPTIONS, PUT and DELETE.
      DEFAULT_ALLOWED_METHODS = ::Set[Method::GET, Method::HEAD].freeze
      # REDIR-17's default cap.
      DEFAULT_MAX_HOPS = 3
      # REDIR-1: the only statuses redirect logic is consulted for.
      RECOGNIZED_CODES = ::Set[301, 302, 303, 307, 308].freeze
      private_constant :RECOGNIZED_CODES

      private_class_method :new

      # Builds a frozen step.
      #
      # @param allowed_methods [Enumerable<Dexpace::Method, String>] the methods a 301, 302,
      #   307 or 308 is followed for, judged on the ORIGINAL request's method; copied and
      #   frozen here (REDIR-26)
      # @param follow303 [Boolean] whether a 303 is followed, as a GET with the body dropped
      # @param max_hops [Integer] the cap on followed redirects, >= 0; 0 disables following
      # @param allow_scheme_downgrade [Boolean] whether an HTTPS -> HTTP hop is permitted
      # @param predicate [#call, nil] `(ConditionSnapshot) -> Boolean`, fully overriding the
      #   built-in follow decision when given (REDIR-20); never the cap, the credential hygiene
      #   or the MUST-not-throw clauses
      # @param logger [Instrumentation::Logger] where REDIR-28's records go, through its own
      #   redactor; Logger::NULL by default
      # @return [Step] frozen
      # @raise [Dexpace::InvalidArgumentError] for an unknown method, a non-boolean flag, a
      #   negative or non-Integer cap, a non-callable predicate or a logger that is not a Logger
      def self.build(allowed_methods: DEFAULT_ALLOWED_METHODS, follow303: false,
                     max_hops: DEFAULT_MAX_HOPS, allow_scheme_downgrade: false, predicate: nil,
                     logger: Instrumentation::Logger::NULL)
        new(allowed_methods: allowed_methods!(allowed_methods),
            follow303: boolean!("follow303", follow303), max_hops: max_hops!(max_hops),
            allow_scheme_downgrade: boolean!("allow_scheme_downgrade", allow_scheme_downgrade),
            predicate: predicate!(predicate), logger: logger!(logger),).freeze
      end

      # REDIR-26: a fresh frozen Set of Methods, decoupled from the caller's collection.
      def self.allowed_methods!(methods)
        ::Set.new(Model.required!("allowed_methods", methods).map { |m| Method.of(m) }).freeze
      end

      def self.boolean!(name, value)
        return value if value.equal?(true) || value.equal?(false)

        raise InvalidArgumentError, "#{name} must be true or false, got #{value.inspect}"
      end

      def self.max_hops!(value)
        return value if value.is_a?(::Integer) && !value.negative?

        raise InvalidArgumentError, "max_hops must be a non-negative Integer, got #{value.inspect}"
      end

      def self.predicate!(predicate)
        return predicate if predicate.nil? || Registry.callable?(predicate, arity: 1)

        raise InvalidArgumentError, "predicate must be callable with (snapshot)"
      end

      def self.logger!(logger)
        return logger if logger.is_a?(Instrumentation::Logger)

        raise InvalidArgumentError, "logger: takes an Instrumentation::Logger, got #{logger.class}"
      end
      private_class_method :allowed_methods!, :boolean!, :max_hops!, :predicate!, :logger!

      def initialize(allowed_methods:, follow303:, max_hops:, allow_scheme_downgrade:, predicate:,
                     logger:)
        @allowed_methods = allowed_methods
        @follow303 = follow303
        @max_hops = max_hops
        @allow_scheme_downgrade = allow_scheme_downgrade
        @predicate = predicate
        @logger = logger
        @emitter = Emitter.new(logger)
      end

      # 4c's optional declaration, read once at install: this is the Stages::REDIRECT pillar.
      #
      # @return [Dexpace::Pipeline::Stage]
      def stage
        Pipeline::Stages::REDIRECT
      end

      # One operation: hops until a non-redirect response, a "return current" outcome or the cap.
      #
      # @param request [Dexpace::Request] the seed
      # @param cursor [Dexpace::Pipeline::Cursor] forked for every drive
      # @return [Dexpace::Response] the terminal response, open
      # @raise [SchemeDowngradeError] on an HTTPS -> HTTP hop without the opt-in (REDIR-15)
      # @raise [Dexpace::NotReplayableError] on a method-preserving hop over a body that
      #   cannot be re-sent (REDIR-6)
      def call(request, cursor)
        chain = Chain.new(request)
        loop do
          response = cursor.fork(state: { cross_origin: chain.cross_origin? }).call(chain.request)
          return response unless RECOGNIZED_CODES.include?(response.status.code) # REDIR-1, 21

          follow_up = closing_on_error(response) { plan(chain, response) }
          return response if follow_up.nil? # a "return current" outcome: open (REDIR-22c)

          commit(chain, response, follow_up)
        end
      end

      private

      # nil for every "return current" outcome, else the follow-up request. REDIR-21's NOTE: on
      # a recognized 3xx the snapshot is ALWAYS allocated and a configured predicate ALWAYS
      # consulted, even with no usable Location; the target is resolved once, before either
      # decision route, and a nil target returns the response unfollowed whatever a predicate
      # answered (REDIR-18 and REDIR-19 are MUSTs no predicate waives). The cap is checked
      # LAST, over the answer (R9, P6-91): placed above the predicate call it would make
      # REDIR-21's "always ... consults the configured predicate" false at the one hop a
      # predicate most wants to be heard, and a predicate cannot lift it (REDIR-17).
      def plan(chain, response)
        target = resolve_target(chain.request.url, response)
        followed = follow?(chain, response, target) # consulted before the cap, whatever the target
        return nil if target.nil? || !followed || chain.count >= @max_hops

        Reissue.build(chain.request, response, target,
                      cross_origin: Origin.cross?(chain.seed, target),
                      allow_scheme_downgrade: @allow_scheme_downgrade, emitter: @emitter,)
      end

      # The decision: the predicate's alone when one is configured, else the built-in one; a nil
      # target is "return current" whatever was answered.
      def follow?(chain, response, target)
        snapshot = ConditionSnapshot.build(response: response, redirect_count: chain.count,
                                           visited_uris: chain.visited,)
        decided = @predicate ? @predicate.call(snapshot) : default_follow?(chain, response, target)
        !target.nil? && decided ? true : false
      end

      # REDIR-19, then REDIR-12 and REDIR-18: never raises. nil is the "return current" signal.
      def resolve_target(current_url, response)
        location = response.headers["Location"]&.first
        return nil if location.nil? || location.empty? # REDIR-19: never reaches the parser

        resolve(current_url, location)
      end

      # REDIR-18's conversion, by class and never by message, at the one site that also logs
      # the raw value (R7).
      def resolve(current_url, location)
        Location.resolve(current_url, location)
      rescue ::URI::InvalidURIError => error
        @emitter.location_malformed(raw: location, error: error) # REDIR-28's raw exception
        nil
      end

      # The built-in decision, in the order the clauses bite.
      def default_follow?(chain, response, target)
        return false if target.nil?

        if chain.visited.include?(URL.external_form(target)) # REDIR-16
          @emitter.loop_detected(from: chain.request.url, to: target, redirect_count: chain.count)
          return false
        end
        return @follow303 if response.status.code == 303 # REDIR-5

        @allowed_methods.include?(chain.seed_method) # REDIR-3, REDIR-4: the ORIGINAL method
      end

      # REDIR-22a, and it is an ORDERING clause: the superseded response is closed BEFORE the
      # next fork goes out, never after it returns -- deferred past the next send it would hold
      # hop N's connection for the whole of hop N+1. Then the record, then the state.
      def commit(chain, response, follow_up)
        Dexpace.close_quietly(response, logger: @logger)
        @emitter.hop(from: chain.request.url, to: follow_up.url, status: response.status,
                     redirect_count: chain.count,)
        chain.advance!(follow_up)
      end

      # REDIR-22b: whatever the block raises, the current response is closed first -- a close
      # failure riding the error's suppressed trail -- and the raise propagates unchanged.
      def closing_on_error(response)
        yield
      rescue ::Exception => error # rubocop:disable Lint/RescueException -- close, then re-raise unchanged (REDIR-22b)
        Dexpace.close_quietly(response, onto: error)
        raise
      end
    end
  end
end
