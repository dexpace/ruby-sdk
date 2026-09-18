# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../registry"
require_relative "../closeable"
require_relative "../http/request"
require_relative "../http/response"
require_relative "../pipeline/stages"
require_relative "../instrumentation/logger"
require_relative "challenges"
require_relative "https_required_error"

module Dexpace
  module Auth
    # AUTH-27–AUTH-36 on the sync runtime: the AUTH pillar step at Stages::AUTH (order 800),
    # nested inside the redirect and retry loops by PIPE-2's stage order, which phase 4c fixed
    # -- AUTH-27's "redirect wraps retry wraps auth" is that table and not a call this class
    # makes. It forks for EVERY drive, the first included, and never calls Cursor#call (P4-39,
    # spec-forced boundary 1): AUTH-30's replay is the case a reader writes as call-then-fork,
    # and #fork after #call raises PipelineError.
    #
    # #call's order is the contract, and AUTH-29 fixes it. The cross-origin check comes FIRST:
    # on a cross-origin redirect re-issue -- read as `cursor.state(Stages::REDIRECT)` carrying a
    # truthy :cross_origin, the marker the redirect step forks into its own slot (design §10.15)
    # -- the step stamps nothing, guards nothing and drives the request as it is. Nothing is
    # stripped, because nothing was ever added to the request: the marker is cursor state and
    # never a header, so AUTH-29's stripping clause is satisfied by construction. The read is
    # keyed by (stage, key), so a RETRY step between REDIRECT and AUTH cannot write the value
    # this step reads, and a request header cannot either: the mechanism can only SUPPRESS a
    # stamp, never cause one. Then the HTTPS guard (AUTH-28), before any fetch or header write;
    # then the stamper; then the drive; then the 401 handling -- the bearer branch (AUTH-36)
    # before the challenge hook (AUTH-30), each gated on AUTH-31's replayability through one
    # private predicate both runtimes inherit (6c's P6-7; spec-forced boundary 13).
    #
    # Step does not dispatch on a credential class and has no #stamp of its own: `stamper:`
    # decides at construction -- KeyStamper, BasicHandler (preemptive Basic), BearerStamper, or
    # NO_STAMP for the NO_AUTH sentinel. Challenge-driven schemes are reached only through
    # `challenge_hook:`, whose default yields no replacement (AUTH-30); Digest arrives when a
    # caller passes ChallengeHandlerChain#as_challenge_hook. The step's one logger use is
    # §3.7's second disposal route for a superseded 401 that fails to close.
    #
    # Built through .build with .new private, the shape phase 5b's step took; frozen, holding
    # three references and no per-request state (PIPE-11).
    class Step
      private_class_method :new

      # AUTH-30's default challenge hook: no replacement, no retry.
      NO_REPLACEMENT = ->(_challenge, _request, _response) {}
      # AUTH-1's NO_AUTH sentinel as a stamper: the request unchanged. The HTTPS guard still
      # runs, because Step cannot know the stamper attaches nothing.
      NO_STAMP = ->(request) { request }

      # @param stamper [#call] `(Request) -> Request`, decided at construction
      # @param challenge_hook [#call] `(String, Request, Response) -> Request | nil` (AUTH-30)
      # @param logger [Instrumentation::Logger] for a superseded response's close failure
      # @return [Step] frozen
      # @raise [Dexpace::InvalidArgumentError] for a stamper or hook of the wrong arity
      def self.build(stamper:, challenge_hook: NO_REPLACEMENT, logger: Instrumentation::Logger::NULL)
        stamper!(stamper)
        unless Registry.callable?(challenge_hook, arity: 3)
          raise InvalidArgumentError,
                "challenge_hook must be callable with (challenge, request, response)"
        end

        new(stamper: stamper, challenge_hook: challenge_hook,
            logger: Model.required!("logger", logger),).freeze
      end

      # The stamper shape this runtime drives: `#call(request) -> Request`.
      def self.stamper!(stamper)
        return if Registry.callable?(stamper, arity: 1)

        raise InvalidArgumentError, "stamper must be callable with (request)"
      end
      private_class_method :stamper!

      def initialize(stamper:, challenge_hook:, logger:)
        @stamper = stamper
        @challenge_hook = challenge_hook
        @logger = logger
      end

      # 4c's declaration, read once at install.
      #
      # @return [Dexpace::Pipeline::Stage]
      def stage
        Pipeline::Stages::AUTH
      end

      # @param request [Dexpace::Request]
      # @param cursor [Dexpace::Pipeline::Cursor]
      # @return [Dexpace::Response]
      # @raise [HTTPSRequiredError] on a non-HTTPS URL where a credential would be attached
      def call(request, cursor)
        return cursor.fork.call(request) if cross_origin?(cursor) # AUTH-29: no guard, no stamp

        enforce_https!(request) # AUTH-28: before any fetch or stamp
        stamped = @stamper.call(request)
        response = cursor.fork.call(stamped)
        return response unless unauthorized?(response)

        challenge = challenge_header(response)
        return response if challenge.nil? # AUTH-33: the hook is never consulted

        retried = bearer_retry(challenge, stamped, response, cursor) # AUTH-36
        return retried unless retried.nil?

        replay(challenge, stamped, response, cursor) # AUTH-30, AUTH-31, AUTH-32
      end

      private

      # AUTH-29's read: the redirect step's own slot, a shared frozen empty Hash when no
      # redirect step forked (the same-origin answer), truthy meaning suppress.
      def cross_origin?(cursor)
        cursor.state(Pipeline::Stages::REDIRECT)[:cross_origin] ? true : false
      end

      # AUTH-28: the scheme compared case-insensitively with a bare downcase.
      def enforce_https!(request)
        scheme = request.url.scheme.to_s
        return if scheme.downcase == "https"

        raise HTTPSRequiredError.new(scheme: scheme, step: self.class.name.to_s)
      end

      def unauthorized?(response) = response.status.code == 401

      # The WWW-Authenticate value the hook receives: a repeated header's values joined with
      # ", ", which RFC 7235 §4.1 makes one challenge list; nil when the header is absent.
      def challenge_header(response)
        values = response.headers["WWW-Authenticate"]
        return nil if values.nil? || values.empty?

        values.join(", ")
      end

      # AUTH-31's gate, one implementation for both runtimes: a request with no body is
      # replayable; otherwise phase 3b's own predicate decides.
      def replayable?(request)
        body = request.body
        body.nil? || body.replayable?
      end

      def bearer_offered?(challenge)
        Challenges.parse(challenge).any? { |parsed| parsed.scheme == "bearer" }
      end

      # AUTH-36's three surface-unchanged conditions plus P6-7's gate, in that order.
      def bearer_retry?(challenge, stamped)
        @stamper.respond_to?(:evict_if_matches) &&
          !rejected_header(stamped).nil? && bearer_offered?(challenge) && replayable?(stamped)
      end

      def rejected_header(stamped)
        stamped.headers["Authorization"]&.first
      end

      # AUTH-36: evict only the exact token that produced this 401, close the superseded
      # response, and re-stamp ONE retry -- from the cache when another request already
      # refreshed it, from a fresh fetch otherwise. Regardless of HTTP method.
      def bearer_retry(challenge, stamped, response, cursor)
        return nil unless bearer_retry?(challenge, stamped)

        @stamper.evict_if_matches(rejected_header(stamped).to_s)
        Dexpace.close_quietly(response, logger: @logger)
        cursor.fork.call(@stamper.call(stamped))
      end

      # AUTH-30: consult the hook; on a replacement, close the 401 and drive the replacement
      # through a fresh fork exactly once, with no further challenge handling. AUTH-31: a
      # non-replayable replacement surfaces the 401 unchanged and UNCLOSED.
      def replay(challenge, stamped, response, cursor)
        replacement = consult(challenge, stamped, response)
        return response if replacement.nil? || !replayable?(replacement)

        Dexpace.close_quietly(response, logger: @logger)
        cursor.fork.call(replacement)
      end

      # AUTH-32: a hook that raises, or returns something that is not a request, leaves the
      # open 401 closed behind it -- the close failure, if any, on the error's suppressed trail.
      def consult(challenge, stamped, response)
        replacement = @challenge_hook.call(challenge, stamped, response)
        replacement!(replacement)
      rescue ::StandardError => error
        Dexpace.close_quietly(response, onto: error)
        raise
      end

      def replacement!(replacement)
        return replacement if replacement.nil? || replacement.is_a?(Request)

        raise InvalidArgumentError,
              "the challenge hook must return a Dexpace::Request or nil, got #{replacement.class}"
      end
    end
  end
end
