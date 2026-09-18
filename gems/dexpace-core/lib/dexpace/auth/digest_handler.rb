# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "digest"
require "securerandom"

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../http/header_syntax"
require_relative "../http/percent_encoding"
require_relative "../bounded_map"
require_relative "password_credential"
require_relative "challenge"
require_relative "unencodable_credential_error"

module Dexpace
  module Auth
    # AUTH-15–AUTH-24: RFC 7616 Digest, challenge-driven by construction -- there is no
    # preemptive #call, because a Digest response needs the server's nonce. Reached from the
    # pillar step only through ChallengeHandlerChain#as_challenge_hook.
    #
    # The hashes are ::Digest::MD5 and ::Digest::SHA256, never OpenSSL::Digest (design §6.3);
    # the cnonce is sixteen SecureRandom bytes, hex-encoded, never Random (AUTH-20, XCUT-21);
    # every hash input is BINARY before it reaches a hasher (HTTP-13's outbound rule).
    #
    # The per-nonce counter store is this instance's own BoundedMap (6c's R11, P6-4): one per
    # handler, constructed here, never shared, its cap an ordinary keyword defaulting to
    # AUTH-19's 1024 and read from no configuration chain -- the handler is explicitly
    # constructed by whoever assembles the pipeline, so the knob was never ambient. The
    # reference is BARE and unqualified, resolved from this full-nesting `module Dexpace;
    # module Auth; class DigestHandler` body: BoundedMap is a private_constant of Dexpace, so
    # `Dexpace::BoundedMap` raises NameError even from inside Dexpace and the compact `module
    # Dexpace::Auth::…` form cannot see it at all (execution-context/b58728da; verified on
    # 3.2.11, 3.4.10 and 4.0.6). The increment is BoundedMap#update, one read-modify-write under
    # the map's own mutex, which is what makes AUTH-24's non-duplicated counts true.
    #
    # Two things the requirements leave to the port, decided here and recorded as 6c's
    # as-built rows. First, a non-ASCII username goes on the wire as RFC 7616 §3.4's
    # `username*=UTF-8''…` (RFC 8187), because HTTP-18's outbound grammar refuses a byte above
    # 0x7F in a header value and the quoted form cannot carry it; the hash still uses the raw
    # username. Second, a challenge whose realm, nonce or opaque cannot be echoed under that
    # grammar is UNSATISFIABLE (AUTH-16, AUTH-25): RFC 7616 defines no encoded form for those
    # three, so the handler declines rather than raise from the header write.
    class DigestHandler # rubocop:disable Metrics/ClassLength -- one algorithm family, one class: selection, the hash chain, the counter and the rendering are one RFC and split by nothing but method
      # AUTH-15's closed algorithm set, in the RFC's canonical spelling (AUTH-22).
      ALGORITHMS = %w[MD5 MD5-sess SHA-256 SHA-256-sess].freeze
      # AUTH-19's default cap on distinct nonces tracked.
      DEFAULT_CAP = 1024

      # The base algorithm of each supported name to its hasher.
      HASHES = { "MD5" => ::Digest::MD5, "SHA-256" => ::Digest::SHA256 }.freeze
      # The challenge parameters echoed verbatim into the response, which must therefore pass
      # the outbound header grammar.
      ECHOED = %w[realm nonce opaque].freeze
      private_constant :HASHES, :ECHOED

      # The values one response is rendered from; private, so #render takes one argument.
      class Computed < ::Data.define(:challenge, :algorithm, :uri, :cnonce, :nc, :qop, :response)
      end
      private_constant :Computed

      # @param credential [PasswordCredential] non-empty username and password (AUTH-14's rule)
      # @param preference [Array<String>] the algorithms to prefer, most preferred first; a
      #   subset of ALGORITHMS
      # @param cap [Integer] AUTH-19's bound on distinct nonces tracked
      # @param cnonce_source [#hex] the random source; SecureRandom, and never Random
      # @raise [Dexpace::InvalidArgumentError] on an empty credential field, an unsupported
      #   algorithm in the preference, or a source with no #hex
      def initialize(credential, preference: ALGORITHMS, cap: DEFAULT_CAP,
                     cnonce_source: ::SecureRandom)
        @credential = credential!(credential)
        @preference = preference!(preference)
        unless cnonce_source.respond_to?(:hex)
          raise InvalidArgumentError, "cnonce_source must answer #hex(bytes)"
        end

        @cnonce_source = cnonce_source
        @nonces = BoundedMap.new(cap: cap) # per handler, never shared (R11)
        freeze
      end

      # AUTH-23's one-method handler protocol (6c's P6-2): the header VALUE for the first
      # satisfiable challenge by the configured preference, or nil when none is (AUTH-25).
      #
      # @param challenges [Array<Challenge>]
      # @param request [Dexpace::Request] its method and request-target enter the hash
      # @param proxy [Boolean] unused here; the chain selects the header name from it
      # @return [String, nil]
      # @raise [UnencodableCredentialError] when the username or password cannot be encoded
      #   under the challenge's encoding (AUTH-21, R10)
      def authorization_for(challenges, request, proxy: false) # rubocop:disable Lint/UnusedMethodArgument -- the handler protocol's signature, which the chain calls uniformly
        challenge = select(challenges)
        return nil if challenge.nil?

        render(compute(challenge, request))
      end

      private

      def credential!(credential)
        unless credential.is_a?(PasswordCredential)
          raise InvalidArgumentError, "a Dexpace::Auth::PasswordCredential is required"
        end
        if credential.username.empty? || credential.password.empty?
          raise InvalidArgumentError, "username and password must be non-empty (AUTH-14)"
        end

        credential
      end

      def preference!(preference)
        list = Model.required!("preference", preference)
        unless list.is_a?(::Array) && !list.empty? && list.all? { |name| ALGORITHMS.include?(name) }
          raise InvalidArgumentError,
                "preference must be a non-empty subset of #{ALGORITHMS.join(", ")} (AUTH-15)"
        end

        Model.own(list)
      end

      # AUTH-16: filter to the satisfiable challenges, then walk the PREFERENCE list rather
      # than the challenge list, which is what makes "independent of the order challenges
      # arrived in" literal rather than incidental.
      def select(challenges)
        satisfiable = challenges.select { |challenge| satisfiable?(challenge) }
        @preference.each do |algorithm|
          found = satisfiable.find { |challenge| algorithm_of(challenge) == algorithm }
          return found unless found.nil?
        end
        nil
      end

      # AUTH-16's four conditions, plus the echo condition the class comment states.
      def satisfiable?(challenge)
        params = challenge.params
        challenge.scheme == "digest" && params.key?("realm") && params.key?("nonce") &&
          (params["qop"].nil? || qop_auth?(challenge)) && !algorithm_of(challenge).nil? &&
          echoable?(params)
      end

      # The three echoed values must pass the outbound header grammar, byte for byte.
      def echoable?(params)
        ECHOED.all? do |key|
          value = params[key]
          value.nil? || HeaderSyntax.valid_outbound_value?(value)
        end
      end

      # The challenge's algorithm in the canonical spelling; nil when unsupported. Absent
      # defaults to MD5 (AUTH-16); the token is matched with a bare, ASCII-only fold, never
      # casecmp? (Dexpace/NoLocaleCaseFold).
      def algorithm_of(challenge)
        token = challenge.params["algorithm"]
        return "MD5" if token.nil?

        wanted = token.b.downcase
        ALGORITHMS.find { |name| name.downcase == wanted }
      end

      # AUTH-15, AUTH-16: qop is a comma-separated TOKEN LIST and the comparison is
      # token-exact -- `"auth-int".include?("auth")` is true, so a substring test would accept
      # exactly the auth-int-only challenge AUTH-15 requires be declined.
      def qop_auth?(challenge)
        challenge.params["qop"].to_s.b.split(",").any? { |token| token.strip.downcase == "auth" }
      end

      # AUTH-17: the values one response is rendered from, for one challenge and one request.
      # The credential is materialised FIRST -- the one step that can raise (AUTH-21) -- and the
      # nonce count taken after it, so a refused attempt consumes no count and the next response
      # on that nonce is not one higher than the server has seen (AUTH-18; the design's own order).
      def compute(challenge, request)
        ha1_parts = credential_bytes(challenge.params)
        algorithm = algorithm_of(challenge).to_s
        cnonce = @cnonce_source.hex(16) # AUTH-20: 128 bits from a CSPRNG
        nonce = challenge.params.fetch("nonce")
        computed = Computed.new(challenge: challenge, algorithm: algorithm, cnonce: cnonce,
                                uri: request_target(request), nc: next_count(nonce),
                                qop: qop_auth?(challenge) ? "auth" : nil, response: nil,)
        computed.with(response: response_for(computed, request.method.to_s, ha1_parts))
      end

      # AUTH-17: HA1, HA2 over the method and the request-target, then the response.
      def response_for(computed, method, ha1_parts)
        hasher = HASHES.fetch(computed.algorithm.delete_suffix("-sess"))
        ha1 = ha1_for(computed, hasher, ha1_parts)
        ha2 = hasher.hexdigest(join(method, computed.uri))
        response_digest(hasher, computed, ha1, ha2)
      end

      # The qop=auth response, or the legacy RFC 2069 no-qop one.
      def response_digest(hasher, computed, ha1, ha2)
        nonce = computed.challenge.params.fetch("nonce")
        return hasher.hexdigest(join(ha1, nonce, ha2)) if computed.qop.nil?

        hasher.hexdigest(join(ha1, nonce, computed.nc, computed.cnonce, computed.qop, ha2))
      end

      # H(username:realm:password) over the materialised components, then session-keyed with
      # the nonce and cnonce for a -sess algorithm.
      def ha1_for(computed, hasher, ha1_parts)
        ha1 = hasher.hexdigest(join(*ha1_parts))
        return ha1 unless computed.algorithm.end_with?("-sess")

        hasher.hexdigest(join(ha1, computed.challenge.params.fetch("nonce"), computed.cnonce))
      end

      # The three HA1 components as BINARY, under AUTH-21's encoding for this challenge, each
      # materialised under its own field name so the typed failure can say which one could not
      # be encoded (R10). The charset token is compared with a bare, ASCII-only fold.
      def credential_bytes(params)
        utf8 = params["charset"].to_s.b.downcase == "utf-8"
        target = utf8 ? ::Encoding::UTF_8 : ::Encoding::ISO_8859_1
        [materialize(@credential.username, :username, target),
         materialize(params.fetch("realm"), :realm, target),
         materialize(@credential.password, :password, target),]
      end

      # AUTH-21: UTF-8 when the challenge advertises charset=UTF-8, ISO-8859-1 otherwise -- and
      # either branch RAISES the typed failure naming ITS target, never `:replace` (R10, P6-1).
      # The Latin-1 branch is the one RFC 7616's default makes ordinary (a character Latin-1 has
      # no code for). The UTF-8 branch fires only for a value that is not text under its own tag
      # -- a BINARY-tagged one, whose high bytes have no UTF-8 meaning, or a UTF-8-tagged one
      # with an invalid sequence, which `encode` to the same encoding passes through unvalidated
      # and would otherwise be hashed as it is (verified on 3.2.11, 3.4.10 and 4.0.6). The
      # rescued conversion error is NOT the cause: its message names the offending character of
      # the secret, and #full_message renders a cause (AUTH-8; 6c's P6-85). `cause: nil` on both
      # raises, so neither picks up a caller's in-flight `$!` either.
      def materialize(text, field, target)
        encoded = text.encode(target)
        return encoded.b if encoded.valid_encoding?

        raise unencodable(text, field, target), cause: nil
      rescue ::Encoding::UndefinedConversionError, ::Encoding::InvalidByteSequenceError
        raise unencodable(text, field, target), cause: nil
      end

      def unencodable(text, field, target)
        UnencodableCredentialError.new(field: field, encoding: target.name,
                                       source_encoding: text.encoding.name,)
      end

      # Every hash input is BINARY, so the joiner is too.
      def join(*parts)
        parts.map(&:b).join(":".b)
      end

      # AUTH-18, AUTH-19, AUTH-24: one read-modify-write under the map's own mutex; a nonce
      # the map has not seen (including one the drain evicted) starts at 1, rendered as exactly
      # 8 lower-case hex digits from the low 32 bits.
      def next_count(nonce)
        count = @nonces.update(nonce) { |current| (current || 0) + 1 }
        format("%08x", count & 0xFFFFFFFF)
      end

      # AUTH-22: the request-target form -- the raw path, "/" when empty, then "?" and the raw
      # query when there is one.
      def request_target(request)
        path = request.url.path
        path = "/" if path.nil? || path.empty?
        query = request.url.query
        query.nil? ? path : "#{path}?#{query}"
      end

      # AUTH-22: username, realm, nonce, uri, response, cnonce and opaque quoted with
      # backslash-escaping; qop, nc and algorithm bare, the algorithm in its full RFC spelling;
      # cnonce, nc and qop only when qop was negotiated; opaque only when the challenge sent it.
      def render(computed)
        parts = [username_field, *echoed(computed), *negotiated(computed),
                 quoted("response", computed.response.to_s), *opaque(computed),]
        "Digest #{parts.join(", ")}"
      end

      # The realm and nonce echoed from the challenge, the uri and the algorithm.
      def echoed(computed)
        params = computed.challenge.params
        [quoted("realm", params.fetch("realm")), quoted("uri", computed.uri),
         "algorithm=#{computed.algorithm}", quoted("nonce", params.fetch("nonce")),]
      end

      # The three fields that exist only when qop was negotiated.
      def negotiated(computed)
        return [] if computed.qop.nil?

        ["nc=#{computed.nc}", quoted("cnonce", computed.cnonce), "qop=#{computed.qop}"]
      end

      # Echoed only when the challenge sent one.
      def opaque(computed)
        value = computed.challenge.params["opaque"]
        value.nil? ? [] : [quoted("opaque", value)]
      end

      def quoted(name, value) = %(#{name}="#{quote(value)}")

      # RFC 7616 §3.4: `username` as a quoted-string when the outbound grammar can carry it,
      # `username*` in RFC 8187's UTF-8 form otherwise. PercentEncoding's RFC 3986 unreserved
      # set is a subset of RFC 8187's attr-char, so its output is valid there.
      def username_field
        name = @credential.username
        if HeaderSyntax.valid_outbound_value?(name)
          quoted("username", name)
        else
          "username*=UTF-8''#{PercentEncoding.encode_component(name.encode(::Encoding::UTF_8))}"
        end
      end

      # The two characters a quoted-string escapes, without a regexp; the block form, because a
      # replacement String has its own backslash grammar.
      def quote(value)
        value.gsub("\\") { "\\\\" }.gsub('"') { '\\"' }
      end
    end
  end
end
