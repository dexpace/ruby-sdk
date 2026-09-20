# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "closeable"
require_relative "model"
require_relative "error/invalid_argument_error"
require_relative "http/request"
require_relative "http/response"
require_relative "http/url"

module Dexpace
  # One page of a paginated walk (PAGE-2, PAGE-3), and the namespace of the whole pagination
  # subsystem -- Info, the three built-in strategies, the two views, the two engines and the
  # fetcher front-end all nest here (P7-2). Design §7.1 names exactly one identifier for the
  # subsystem, `Dexpace::Page`, and appendix A calls the value "a Page"; nesting the rest inside
  # it keeps `lib/dexpace/page/**` as one audited directory. None of the nested names shadows a
  # Ruby core constant or a `Dexpace::` one (the smoke suite pins the list).
  #
  # A page owns exactly one live Dexpace::Response, and whoever holds the page owns closing it:
  # the component that fetched the response hands ownership over the moment it builds the page
  # (PAGE-3). The materialized items and the derived status, headers and originating request
  # stay readable after #close, because they are read off a frozen Data that closing does not
  # touch; only the body is invalidated (PAGE-2).
  #
  # A plain class including Dexpace::Closeable, deliberately NOT a Data. A Data instance is
  # frozen and cannot hold the latch (phase 3b's finding, applied one layer up), and the latch
  # cannot be borrowed from the response either: Response#close is a pure forward to the body,
  # and the body slot may hold nil, a BufferBody whose #close is a documented no-op, or -- only
  # in the transport case -- a latching ResponseBody. So PAGE-27's exactly-once close, on every
  # path that consumes a page, is a property of the page itself: the latch is here, #release
  # forwards to the response once, and a second #close returns without touching it.
  class Page
    include Dexpace::Closeable

    private_class_method :new

    # The validating factory every page goes through: a real Dexpace::Response (checked the way
    # Response#initialize checks its request), an Array of items, copied shallowly and frozen
    # -- the collection is the model's, its elements stay the caller's (HTTP-5, XCUT-15; a deep
    # copy through Model.own would replace and freeze domain objects and raise on a Proc, P7-101)
    # -- and the two PAGE-34 keys, each nil or a String copied frozen, exactly as Info holds them:
    # a key of another class is named and refused here rather than discovered by the fetcher
    # front-end as a NoMethodError when it keys the next page off it (P7-107).
    #
    # @param response [Dexpace::Response] the live response this page owns from now on
    # @param items [Array] the materialized items, possibly empty, never nil (PAGE-2)
    # @param next_link [String, nil] PAGE-34's next link, when the source carried one
    # @param continuation_token [String, nil] PAGE-34's fallback key
    # @return [Dexpace::Page]
    # @raise [Dexpace::InvalidArgumentError] on a missing response, a non-Array items, or a link
    #   or token that is neither nil nor a String
    def self.build(response:, items:, next_link: nil, continuation_token: nil)
      unless Model.required!("response", response).is_a?(Dexpace::Response)
        raise InvalidArgumentError, "response must be a Dexpace::Response, got #{response.class}"
      end
      unless Model.required!("items", items).is_a?(::Array)
        raise InvalidArgumentError, "items must be an Array, got #{items.class}"
      end

      new(response, items, next_link, continuation_token)
    end

    # PAGE-19's whole answer, shipped once: the next request for a rel=next target -- or any
    # URL a strategy found in a header, a body or elsewhere -- resolved against the originating
    # page's response URL, or nil for end-of-stream. Public rather than private to LinkStrategy
    # because a next-page URL in the response BODY is the one shape a generated client commonly
    # needs that none of the three built-ins covers, and a caller-written #parse that re-derives
    # this branch by hand gets the two end-of-stream rules quietly wrong (P7-2).
    #
    # Four routes to nil, in order: a nil, blank or whitespace-only target is end-of-stream
    # BEFORE resolution is attempted, because `URI::RFC3986_PARSER.join(base, "")` succeeds and
    # answers the base itself, so `<>; rel=next` would otherwise loop until the page cap (P7-5);
    # a target that cannot resolve at all is end-of-stream, never an error (PAGE-19's own text);
    # and a target that resolves to something this client cannot dispatch -- no http or https
    # scheme, or no host: `mailto:`, `javascript:`, `http:foo`, `http:///p`, every one a
    # SUCCESSFUL join -- is end-of-stream too, consistent with REDIR-18's screen in the redirect
    # step (P7-104). Otherwise `template.with(url:)`, which is PAGE-23's "swap only the URL,
    # preserving the template's method, headers and body": Model#with routes through
    # Request.build, so the other three members travel unchanged and HTTP-7 is re-validated.
    #
    # @param template [Dexpace::Request] the original request template
    # @param response [Dexpace::Response] the page whose URL is the resolution base
    # @param target [String, nil] the raw target, absolute or relative
    # @return [Dexpace::Request, nil] nil is the end-of-stream signal (PAGE-4)
    def self.next_request_from(template, response, target)
      return nil if target.nil? || target.strip.empty?

      resolved = Dexpace::URL.resolve(response.request.url, target)
      return nil if resolved.nil? || !dispatchable?(resolved)

      template.with(url: resolved)
    end

    # The schemes this client dispatches; the same two the redirect step screens for.
    DISPATCHABLE_SCHEMES = %w[http https].freeze
    private_constant :DISPATCHABLE_SCHEMES

    # 6b's screen, copied rather than called: Redirect::Location is a private_constant.
    def self.dispatchable?(target)
      scheme = target.scheme
      host = target.host
      !scheme.nil? && DISPATCHABLE_SCHEMES.include?(scheme.downcase) && !host.nil? && !host.empty?
    end
    private_class_method :dispatchable?

    def initialize(response, items, next_link, continuation_token)
      @response = response
      @items = items.dup.freeze
      @next_link = optional_string("next_link", next_link)
      @continuation_token = optional_string("continuation_token", continuation_token)
      initialize_closeable(owned: true)
    end

    # @return [Dexpace::Response] the live response; its body is invalid once the page is closed
    attr_reader :response
    # @return [Array] the frozen materialized items, readable after close (PAGE-2)
    attr_reader :items
    # @return [String, nil] PAGE-34's next link, as the source supplied it
    attr_reader :next_link
    # @return [String, nil] PAGE-34's continuation token, the fallback key
    attr_reader :continuation_token

    # @return [Dexpace::Status] the response's status, readable after close (PAGE-2)
    def status = @response.status

    # @return [Dexpace::Headers] the response's headers, readable after close (PAGE-2)
    def headers = @response.headers

    # @return [Dexpace::Request] the originating (executed) request, readable after close (PAGE-2)
    def request = @response.request

    private

    # nil, or a frozen copy of the String (XCUT-15); anything else is named and refused -- the same
    # rule Info applies to the same two members, so a key travels from an Info to a Page unchanged.
    def optional_string(name, value)
      return nil if value.nil?
      return Model.frozen_string(value) if value.is_a?(::String)

      raise InvalidArgumentError, "#{name} must be a String or nil, got #{value.class}"
    end

    # Closeable's one obligation: forward to the response exactly once. A raising close leaves the
    # latch flipped, so no second release is attempted and the failure propagates once (PAGE-3).
    def release
      @response.close
    end
  end
end
