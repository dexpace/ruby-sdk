# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../http/response"

module Dexpace
  module Redirect
    # REDIR-20's READ-ONLY, defensively-copied condition snapshot: what a configured redirect
    # predicate is handed for a recognized 3xx -- the current response, the count of redirects
    # already followed, and the insertion-ordered set of visited URIs, the current request's
    # included. It crosses into caller code, so it is public API and follows the phase-1
    # construction pattern (R9): `.new` private, a validating keyword `.build`, `Model.required!`
    # naming the member, and `#with` through `.build` (Model#with).
    #
    # `visited_uris` is a frozen Set of Dexpace::URL.external_form Strings, seeded with the
    # seed request's URL and grown by one entry per followed hop, copied through Model.own at
    # construction so the predicate cannot reach the loop's live cycle-detection state -- the
    # copy is what REDIR-20's "cannot mutate" rests on, and the frozen Set is what makes the
    # attempt a FrozenError rather than a silent write to a discarded copy. Strings and not
    # URI objects: the external form is the wire-exact rendering REDIR-13 preserves, and the
    # loop compares by it (verified fact 4: Set is insertion-ordered).
    #
    # The response is the live, OPEN redirect response; the predicate may read its status and
    # headers and must not close it -- every "return current" outcome hands it back to the
    # caller open (REDIR-22c).
    class ConditionSnapshot < Data.define(:response, :redirect_count, :visited_uris)
      include Model

      private_class_method :new

      # The validating factory every construction path goes through.
      #
      # @param response [Dexpace::Response] the current redirect response, open
      # @param redirect_count [Integer] redirects already followed, >= 0
      # @param visited_uris [Enumerable<String>] the external forms visited so far, copied
      # @return [ConditionSnapshot] frozen
      # @raise [Dexpace::InvalidArgumentError] naming the member, on any invalid value
      def self.build(response:, redirect_count:, visited_uris:)
        new(response: response, redirect_count: redirect_count, visited_uris: visited_uris)
      end

      def initialize(response:, redirect_count:, visited_uris:)
        unless Model.required!("response", response).is_a?(Response)
          raise InvalidArgumentError, "response must be a Dexpace::Response"
        end

        count = Model.required!("redirect_count", redirect_count)
        unless count.is_a?(::Integer) && !count.negative?
          raise InvalidArgumentError, "redirect_count must be a non-negative Integer"
        end

        visited = ::Set.new(Model.required!("visited_uris", visited_uris))
        super(response: response, redirect_count: count, visited_uris: Model.own(visited))
      end
    end
  end
end
