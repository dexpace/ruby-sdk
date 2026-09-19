# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../http/url"
require_relative "origin"

module Dexpace
  module Redirect
    # The per-operation locals of one Step#call (PIPE-11: on the stack, never on the step): the
    # seed request's origin triple and method, the current request, the count of redirects
    # followed, and the visited set -- REDIR-16's, seeded with the seed's URL and grown by one
    # external form per followed hop, so it is also REDIR-20's "visited URIs including the
    # current request's". The seed's METHOD is kept beside its origin because REDIR-3 and
    # REDIR-4 judge "the ORIGINAL request method": after a 303 GET rebuild the chain continues
    # under GET, which the default set admits, while a seed POST does not.
    #
    # A private_constant with a sig/ mirror, asserted through Step's suite; not public API.
    class Chain
      attr_reader :request, :count, :visited, :seed, :seed_method

      def initialize(request)
        @request = request
        @seed = Origin.of(request.url)
        @seed_method = request.method
        @visited = ::Set[URL.external_form(request.url)]
        @count = 0
      end

      # REDIR-8: the current hop against the SEED origin; false on the seed's own drive.
      def cross_origin? = Origin.cross?(@seed, @request.url)

      # One hop followed: the target joins the visited set, the follow-up becomes the current
      # request, the count goes up.
      def advance!(follow_up)
        @visited << URL.external_form(follow_up.url)
        @request = follow_up
        @count += 1
      end
    end
    private_constant :Chain
  end
end
