# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "headers"
require_relative "method"
require_relative "url"

module Dexpace
  # An HTTP request: exactly method, target URL, headers and an optional body (HTTP-6).
  #
  # `url` is the frozen URI::Generic that URL.parse! returned; `headers` is a Headers, never nil
  # and possibly empty, and always one the OUTBOUND grammar validated -- a request's headers are
  # caller-set, which is what HTTP-18 governs, and XCUT-18 puts that check at the model layer
  # before any transport; an inbound-validated collection admits obs-text and would hand every
  # later derivation a lenient builder, so it is refused whatever it holds; `body` is opaque in
  # phase 1 -- the BODY model is phase 3's, so the member is carried, HTTP-7's presence check is
  # the only thing asked of it, and its signature is `untyped` until phase 3b narrows it.
  #
  # #method deliberately shadows Object#method, exactly as Net::HTTPGenericRequest#method does;
  # Object#instance_method remains available to anyone who needs the callable. And the second
  # hole design §10.10 admits is stated here rather than tested: any object responding to
  # #method, #url, #headers and #body duck-types past the builder, which is a property of Ruby,
  # and the transport-side re-validation of HTTP-17/HTTP-18 is what bounds it.
  #
  # The member IS named `method`: HTTP-6 fixes the four members by name, and the shadowing of
  # Object#method is the deliberate choice documented above, so the lint's "may be unexpected"
  # is answered rather than accepted.
  class Request < Data.define(:method, :url, :headers, :body) # rubocop:disable Lint/DataDefineOverride
    include Model

    private_class_method :new

    # The validating factory every construction path goes through.
    def self.build(method:, url:, headers:, body: nil)
      new(method: method, url: url, headers: headers, body: body)
    end

    # A builder with nothing set.
    def self.builder
      Builder.new
    end

    # Coerce, do not merely check. `.build` is public and #with routes through it, so
    # `Request.build(method: "GET", url: "https://h/")` has to yield a Method and a URI rather than
    # a String that behaves like one until the first `#body_forbidden?` call. Both factories are
    # idempotent on their own type, so the coercion is free when the caller already did it. And
    # the model, not only the builder, enforces HTTP-7: a rule that lived only in
    # Request::Builder#build would let `get_request.with(body: "payload")` produce a GET carrying
    # a body -- the exact state HTTP-7 exists to make unrepresentable.
    def initialize(method:, url:, headers:, body:)
      http_method = Method.of(Model.required!("method", method))
      target = URL.parse!(url)
      unless Model.required!("headers", headers).is_a?(Headers)
        raise InvalidArgumentError, "headers must be a Dexpace::Headers"
      end
      unless headers.direction == :outbound
        raise InvalidArgumentError, "headers must be validated by the outbound grammar (HTTP-18)"
      end
      if http_method.body_forbidden? && !body.nil?
        raise InvalidArgumentError, "a #{http_method} request must not carry a body (HTTP-7)"
      end

      super(method: http_method, url: target, headers: headers, body: body)
    end

    # HTTP-3: a builder pre-filled from this instance; the headers are a frozen model and the
    # builder derives its own from them, so nothing is aliased.
    def new_builder
      Builder.new(method: method, url: url, headers: headers, body: body)
    end

    # HTTP-46: URLs compare by textual external form and nothing else. Data's generated equality
    # would compare URI::Generic objects, which is URI's own normalising relation and a different
    # one -- and the requirement is stated in terms of the external form. Ruby's URI performs no
    # DNS, so "MUST NOT perform blocking work or name resolution" holds structurally; the test
    # asserts it (api-design/e4fa3438 permits the override with this comment).
    def ==(other)
      other.is_a?(Request) &&
        URL.external_form(url) == URL.external_form(other.url) &&
        method == other.method && headers == other.headers && body == other.body
    end
    alias eql? ==

    # Agrees with #==.
    def hash
      [Request, URL.external_form(url), method, headers, body].hash
    end
  end
end
