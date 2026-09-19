# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/not_replayable_error"
require_relative "../http/method"
require_relative "../http/request"
require_relative "../resilience/resend"
require_relative "scheme_downgrade_error"

module Dexpace
  module Redirect
    # Builds the follow-up request for one hop, or raises: the rules that turn "we are following
    # this redirect" into the request that goes out, in the order they bite. REDIR-15's
    # downgrade check first, per hop, emitted under the outcome's own name and refused without
    # the opt-in; then the header hygiene -- REDIR-7's Authorization strip on EVERY re-issue,
    # unconditionally, and REDIR-9's Cookie and Proxy-Authorization strip on a cross-origin hop
    # only, REDIR-10 keeping Cookie same-origin -- as a REMOVE on a fresh Headers::Builder, never
    # a second add (Request::Builder#header appends); then either REDIR-5's 303 rebuild -- a
    # GET, no body, every `Content-*` header removed by PREFIX under the no-argument fold, never
    # by a fixed list, or Content-MD5 and Content-Language survive a body that does not -- or,
    # for 301/302/307/308, REDIR-6's replayable-body gate through 6a's
    # Resilience::Resend.replayable_body? (never .eligible?, which folds in RETRY-7's
    # idempotency clause and would refuse a body-less POST 307 the allowed set admits) and a
    # re-issue with the method AND the body preserved (REDIR-3, REDIR-4: no POST -> GET rewrite).
    #
    # Every raise here happens inside Step's closing frame, so the current response is closed
    # before it propagates (REDIR-22b). Functions with no state, over the step's opt-in flag and
    # its emitter; a private_constant with a sig/ mirror, asserted through Step's suite.
    module Reissue
      extend self

      # @param request [Dexpace::Request] the current hop's request
      # @param response [Dexpace::Response] the current redirect response, open
      # @param target [URI::Generic] the resolved, stripped, frozen target
      # @param cross_origin [Boolean] the target judged against the SEED origin (REDIR-8)
      # @param allow_scheme_downgrade [Boolean] REDIR-15's opt-in
      # @param emitter [Emitter] where the downgrade record goes
      # @return [Dexpace::Request]
      # @raise [SchemeDowngradeError] REDIR-15, without the opt-in
      # @raise [Dexpace::NotReplayableError] REDIR-6, on a present, non-replayable body
      def build(request, response, target, cross_origin:, allow_scheme_downgrade:, emitter:)
        downgrade!(request.url, target, allow_scheme_downgrade, emitter)
        headers = strip(request.headers, cross_origin: cross_origin)
        return rebuild_as_get(request, target, headers) if response.status.code == 303

        unless Resilience::Resend.replayable_body?(request)
          raise NotReplayableError, "redirect re-issue"
        end

        request.with(url: target, headers: headers)
      end

      private

      def downgrade!(from, to, permitted, emitter)
        return unless from.scheme.to_s.downcase == "https" && to.scheme.to_s.downcase == "http"

        emitter.scheme_downgrade(from: from, to: to, permitted: permitted)
        return if permitted

        raise SchemeDowngradeError.new(from: from, to: to)
      end

      def strip(headers, cross_origin:)
        builder = headers.new_builder.remove("Authorization")
        builder.remove("Cookie").remove("Proxy-Authorization") if cross_origin
        builder.build
      end

      def rebuild_as_get(request, target, headers)
        builder = headers.new_builder
        headers.names.each { |name| builder.remove(name) if name.downcase.start_with?("content-") }
        request.with(method: Method::GET, url: target, headers: builder.build, body: nil)
      end
    end
    private_constant :Reissue
  end
end
