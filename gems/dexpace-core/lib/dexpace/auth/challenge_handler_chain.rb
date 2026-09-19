# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../http/headers"
require_relative "challenges"

module Dexpace
  module Auth
    # AUTH-23, AUTH-25: the composing challenge handler. Parses the header value once and tries
    # each handler in declaration order, returning the first non-nil header VALUE; nil when
    # none can satisfy any offered challenge -- no header, never an empty one. The handler
    # protocol is one method, `#authorization_for(challenges, request, proxy:) -> String | nil`
    # (6c's P6-2): behaviourally identical to a can-handle query plus a build call, at half
    # the public surface. Callers order stronger schemes first (Digest before Basic); the
    # chain reorders nothing.
    #
    # #as_challenge_hook is the adapter that makes the chain reachable from the pillar step,
    # and it is where AUTH-25's header NAME -- Authorization for a WWW-Authenticate challenge,
    # Proxy-Authorization for a Proxy-Authenticate one, chosen by the explicit `proxy:` flag
    # and never by inspecting the response -- is written onto a request. It is never installed
    # by default: AUTH-30's "the default hook MUST yield no replacement" is Step::NO_REPLACEMENT,
    # and a caller opts in by passing this.
    class ChallengeHandlerChain
      # @param handlers [Array<#authorization_for>] tried in this order; copied at construction
      #   so later caller mutation cannot reorder it (AUTH-23)
      def initialize(handlers)
        list = Model.required!("handlers", handlers)
        raise InvalidArgumentError, "handlers must be an Array" unless list.is_a?(::Array)
        unless list.all? { |handler| handler.respond_to?(:authorization_for) }
          raise InvalidArgumentError, "every handler must answer #authorization_for"
        end

        @handlers = list.dup.freeze
        freeze
      end

      # @param header_value [String, nil] the WWW-Authenticate or Proxy-Authenticate value
      # @param request [Dexpace::Request] the request being answered
      # @param proxy [Boolean] whether the challenge was a proxy's
      # @return [String, nil] the first handler's header value, or nil (AUTH-25)
      def authorization_for(header_value, request, proxy: false)
        challenges = Challenges.parse(header_value)
        @handlers.each do |handler|
          value = handler.authorization_for(challenges, request, proxy: proxy)
          return value unless value.nil?
        end
        nil
      end

      # AUTH-25: the header name, from the flag alone.
      #
      # @param proxy [Boolean]
      # @return [String]
      def header_name(proxy:)
        proxy ? "Proxy-Authorization" : "Authorization"
      end

      # AUTH-30's hook contract is "a replacement request or nil"; a handler returns a header
      # value; this is where the two meet. The replacement SETS the header, so a preemptive
      # stamp on the rejected request is replaced rather than joined by a second value.
      #
      # @param proxy [Boolean] which header the hook writes
      # @return [Proc] a three-argument hook: (header value, request, response) -> Request | nil
      def as_challenge_hook(proxy: false)
        lambda do |header_value, request, _response|
          value = authorization_for(header_value, request, proxy: proxy)
          next nil if value.nil?

          headers = request.headers.new_builder.set(header_name(proxy: proxy), value).build
          request.with(headers: headers)
        end
      end
    end
  end
end
