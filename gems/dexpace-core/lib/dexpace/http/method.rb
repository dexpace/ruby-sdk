# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "header_syntax"

module Dexpace
  # An HTTP method token (HTTP-9).
  #
  # `upcase` with no argument: the same locale rule as HTTP-13's fold, enforced by the same cop.
  # Because the token is upcased at construction and validated against the RFC 7230 token grammar,
  # "each method's canonical wire token equals its uppercase name" holds structurally rather than
  # through a lookup table -- an extension method gets the guarantee too.
  #
  # This class shadows ::Method inside `module Dexpace`, the hazard phase 0 recorded for
  # Dexpace::Serde::JSON and Dexpace::Async::Thread. Inside core a bare `Method` means this class;
  # write `::Method` for Ruby's. Outside core it is inert: a consumer's top-level `Method` still
  # resolves to Ruby's, even after `include Dexpace`, because Object's own constants win over an
  # included module's.
  class Method < Data.define(:token)
    include Model

    private_class_method :new

    # HTTP-9's single source. Phase 6's configurable retry allow-list and its inherent
    # replay-safety gate both derive from this set; neither writes the five names again. Public,
    # because those consumers read it by receiver from sibling files (deviation P1-10).
    IDEMPOTENT = %w[GET HEAD OPTIONS PUT DELETE].freeze

    # The classification HTTP-7 consumes: a body on one of these is rejected at construction
    # rather than deferred to a transport, because reference transports diverge (one throws, one
    # silently drops the body) and rejecting once yields one portable behaviour.
    BODY_FORBIDDEN = %w[GET HEAD TRACE CONNECT].freeze

    # The validating factory every construction path goes through.
    def self.build(token:)
      new(token: token)
    end

    # A String or Symbol token in any casing, or a Method returned as it is.
    def self.of(token)
      return token if token.is_a?(Method)

      build(token: token)
    end

    # Byte check first, then `upcase` -- never the other way round. On "GET\xE9" the upcase would
    # raise ArgumentError before any rule of this SDK had a chance to reject the token, and
    # HeaderSyntax.token? reads bytes so that it returns false on that input instead.
    def initialize(token:)
      Model.required!("token", token)
      unless token.is_a?(String) || token.is_a?(Symbol)
        raise InvalidArgumentError, "token must be a String or Symbol"
      end

      text = token.to_s
      unless HeaderSyntax.token?(text)
        raise InvalidArgumentError, "method must be a valid HTTP token (RFC 7230 tchar)"
      end

      super(token: Model.frozen_string(text.upcase))
    end

    # The canonical wire token.
    def to_s
      token
    end

    # Membership of HTTP-9's idempotent set.
    def idempotent?
      IDEMPOTENT.include?(token)
    end

    # HTTP-7's gate, asked of the method rather than re-listed in Request::Builder.
    def body_forbidden?
      BODY_FORBIDDEN.include?(token)
    end

    # No `private` section: #to_s, #idempotent? and #body_forbidden? are public on purpose, and
    # the placement would be load-bearing -- Request#initialize calls `method.body_forbidden?`
    # with an explicit receiver, so a stray `private` above them fails Task 14 with a
    # NoMethodError. Measured, with that mistake in place: on 4.0.6 (Minitest 6.0.0) two
    # `refute_predicate` cases catch it; on the 3.2.11 floor (Minitest 5.25.1) nothing in the
    # suite does, because assert_predicate and refute_predicate both go through __send__ there.
    # That is why the visibility test uses respond_to?.

    # The nine registered methods, as canonical instances; each equals `Method.of` of its name.
    GET = of("GET")
    # HEAD: idempotent, body forbidden.
    HEAD = of("HEAD")
    # POST: neither idempotent nor body-forbidden.
    POST = of("POST")
    # PUT: idempotent.
    PUT = of("PUT")
    # PATCH: neither idempotent nor body-forbidden.
    PATCH = of("PATCH")
    # DELETE: idempotent.
    DELETE = of("DELETE")
    # OPTIONS: idempotent.
    OPTIONS = of("OPTIONS")
    # TRACE: body forbidden.
    TRACE = of("TRACE")
    # CONNECT: body forbidden.
    CONNECT = of("CONNECT")
  end
end
