# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"

require_relative "../configuration"
require_relative "../instrumentation/keys"
require_relative "../instrumentation/logger"
require_relative "../instrumentation/contain"
require_relative "../instrumentation/redactor"

module Dexpace
  # The resolver behind Dexpace::Proxy.resolve: CFG-24 through CFG-28. Never raises -- "proxies
  # are optional; invalid config yields null and a warning log" -- and the warning is Kernel#warn,
  # phase 2's P2-6 shape (P5-8), with -- since phase 5b -- an `http.instrumentation.config`
  # event emitted BESIDE it through the logger the caller passed, and neither removed. The
  # logger is threaded to the three private methods that warn rather than held on the module,
  # which is stateless.
  #
  # A private_constant on Dexpace (P2-15, P4-3), asserted at its one call site in proxy_test.rb.
  # Everything here reads the chain through CFG-4's raw accessor for the seven system-property
  # names and CFG-1's string accessor for the three environment names, which is §10.16's "one
  # deviation applied twice, not two deviations". The seven names are the resolver's private
  # business, not Configuration::Keys: CFG-14 does not name them and only this file reads them.
  #
  # The four layered names are one frozen hash keyed by layer, so CFG-24's "the port MUST be taken
  # from the SAME layer as the chosen host" is a lookup on the layer the host was found under and
  # never two independent reads -- the clause most likely to be implemented as parallel branches
  # and most likely to pass a test that sets both layers. The credential names and the non-proxy
  # property stay flat because they are deliberately NOT layered: CFG-24 gives credentials no
  # http.* fallback and CFG-26 gives the list one property name.
  #
  # A warning about a URL shows that URL, and a proxy URL is the one configuration value that
  # carries a credential, so the text a warning and its diagnostic carry is the redactor's form
  # of the URL and never the raw value (OBS-11; review round 1's R1-1, P5-103): `#shown` below is
  # the one place the URL is rendered for either channel.
  #
  # Over Metrics/ModuleLength's default, because phase 5b threads the logger to the three
  # methods that warn and renders the URL through the redactor; the exception is recorded here
  # rather than the cap raised, as .rubocop.yml prescribes.
  module ProxyResolution # rubocop:disable Metrics/ModuleLength
    extend self

    # The four layered system-property names, keyed by layer, in CFG-24's preference order.
    LAYERS = {
      https: { host: "https.proxyHost", port: "https.proxyPort" },
      http: { host: "http.proxyHost", port: "http.proxyPort" },
    }.freeze
    # The only username source (CFG-24: no http.* credential fallback).
    CRED_USER = "https.proxyUser"
    # The only password source (CFG-24: no http.* credential fallback).
    CRED_PASS = "https.proxyPassword"
    # The pipe-separated non-proxy list that wins over NO_PROXY (CFG-26).
    NON_PROXY_PROP = "http.nonProxyHosts"

    # CFG-24's own grammar for a proxy URL is `scheme://user:pass@host:port`, so in a proxy URL
    # whatever precedes the last `@` before the first `/`, `?` or `#` is a credential -- even in
    # a value with no `//`, which RFC 3986 reads as an opaque URI with no userinfo and the
    # redactor therefore writes back as given (P5-100). Applied to the redactor's form of the
    # URL before it is shown, so `user:secret@proxy.corp:3128` -- the scheme forgotten -- shows
    # as `***:***@proxy.corp:3128`. One bounded class and one literal; the per-pattern timeout is
    # the port's rule.
    #
    # UNANCHORED, and applied with `gsub` to every `@` the shown form carries (phase 10, repairing
    # phase 5b's R3-1). Anchored at `\A`, the belt reached only a credential in the value's FIRST
    # slash-free run, and a spelling that puts a slash before the userinfo -- `http:/u:p@h:1`,
    # `http:///u:p@h`, `/http://u:p@h:1`, `socks5:/u:p@h:1` -- is read by the parser as a path
    # the redactor keeps verbatim (OBS-14), so the password reached Kernel#warn and the config sink
    # on eight spellings of eight on 4.0.6 and 3.2.11. Over-redacting an `@` that sits in a path is
    # the safe direction in a warning: OBS-11's userinfo rule is "unconditional".
    CREDENTIAL_BEFORE_AT = ::Regexp.new("[^/?#]*@", timeout: 1.0)
    private_constant :CREDENTIAL_BEFORE_AT

    # Where a proxy URL's authority starts: after a `scheme:` that is followed by at least one
    # `/`, or after any leading run of `/` -- never after a bare `user:`, which is the forgotten-
    # scheme spelling's username and part of the credential. Anchored, and no class in it admits
    # the `:` or `/` that ends it, so it cannot backtrack; the per-pattern timeout is the port's
    # rule all the same.
    AUTHORITY_START = ::Regexp.new("\\A(?:[A-Za-z][A-Za-z0-9+.\\-]*:/+|/*)", timeout: 1.0)
    private_constant :AUTHORITY_START

    # The header name #shown renders the URL under: `location`, the first of
    # RedactionPolicy::DEFAULT's URL-valued names, which is what makes Redactor#header_value take
    # the URL route rather than pass the value through (OBS-17).
    SHOWN_AS = "location"
    private_constant :SHOWN_AS

    # CFG-24's two sources, in its order and with its boundary: the environment is consulted only
    # "if no system-property host is set". A system-property host with an unusable port therefore
    # yields nil, never a silent fall-through to HTTPS_PROXY -- which would be CFG-25's "MUST cause
    # resolution to yield null rather than guessing" inverted into guessing elsewhere.
    #
    # @param configuration [Dexpace::Configuration]
    # @param logger [Dexpace::Instrumentation::Logger] where each warning is also reported
    # @return [Dexpace::Proxy, nil]
    def resolve(configuration, logger)
      layer, host = property_host(configuration)
      return from_properties(configuration, layer, host, logger) if layer && host

      from_environment(configuration, logger)
    rescue ::StandardError => error
      # Every input this resolver expects to be malformed is answered by an explicit
      # nil-with-warning above; this is the backstop, last rather than wrapped around the parse
      # alone, because CFG-24's clause is about the operation and not about one call inside it.
      warn_and_nil("proxy resolution failed: #{error.class}: #{error.message}", logger)
    end

    private

    # @return [Array] the layer the host came from and the host, or [nil, nil]
    def property_host(configuration)
      hosts = LAYERS.transform_values { |keys| configuration.raw_property(keys[:host])&.strip }
      hosts.find { |_layer, host| !(host.nil? || host.empty?) } || [nil, nil]
    end

    # The port from the SAME layer as the host, one lookup on `layer`; the credentials from
    # https.proxyUser / https.proxyPassword ONLY, with no http.* fallback, even when the host came
    # from the http.* pair (CFG-24; the chapter's own conformance case).
    def from_properties(configuration, layer, host, logger)
      port_key = LAYERS.fetch(layer)[:port]
      port = parse_port(configuration.raw_property(port_key))
      if port.nil?
        return warn_and_nil("proxy port for #{host} (#{port_key}) is missing, non-numeric or " \
                            "outside 0..65535", logger,)
      end

      model_for(configuration, type: Proxy::Type::HTTP, host: host, port: port,
                               username: configuration.raw_property(CRED_USER),
                               password: configuration.raw_property(CRED_PASS),)
    end

    # HTTPS_PROXY preferred over HTTP_PROXY, parsed as scheme://user:pass@host:port.
    def from_environment(configuration, logger)
      url = environment_url(configuration)
      return nil if url.nil?

      scheme, userinfo, host, port = split_url(url, logger)
      return nil if host.nil?

      username, password = credentials(userinfo)
      model_for(configuration, type: scheme_type(scheme), host: host, port: port,
                               username: username, password: password,)
    end

    # The first NON-BLANK of the two, stripped. A blank HTTPS_PROXY is absent for the preference
    # whichever tier supplied it: CFG-2 already makes an empty environment value fall through, but
    # an override or property of "" is an answer to Configuration#string, and a blank is not a URL,
    # so it must not mask HTTP_PROXY either.
    #
    # @return [String, nil]
    def environment_url(configuration)
      [Configuration::Keys::HTTPS_PROXY, Configuration::Keys::HTTP_PROXY]
        .lazy.filter_map { |key| configuration.string(key)&.strip }.find { |url| !url.empty? }
    end

    # CFG-27's bypass-all yields nil before any model is built.
    def model_for(configuration, type:, host:, port:, username:, password:)
      patterns, bypass_all = non_proxy_hosts(configuration)
      return nil if bypass_all

      Proxy.build(type: type, host: host, port: port, username: username, password: password,
                  non_proxy_hosts: patterns,)
    end

    # URL.parse! is deliberately not used: its contract is to raise, and CFG-24 forbids throwing.
    # CFG-25's absent port is read off split[3] and NEVER off #port: parse("http://h").port is
    # already 80 by the time it is read, so a resolver built on #port passes for "http://h:8080"
    # AND for "http://h" -- resolving the second to 80, the exact behaviour CFG-25 forbids.
    #
    # Both warnings show the URL through #shown and never raw (R1-1): the parser's own message
    # repeats the value it rejected, userinfo included, so it is not quoted either.
    #
    # @return [Array] scheme, userinfo, host and port; empty after a warning
    def split_url(url, logger)
      parser = ::URI::RFC3986_PARSER #: untyped
      scheme, userinfo, host, raw_port = parser.split(url)
      problem = url_problem(host, raw_port)
      return warn_and_nil("proxy URL #{shown(url).inspect} #{problem}", logger) || [] if problem

      [scheme, userinfo, host, parse_port(raw_port)]
    rescue ::URI::InvalidURIError
      warn_and_nil("proxy URL #{shown(url).inspect} is not a URI", logger) || []
    end

    # The URL as a warning may show it (P5-103): the redactor's total header-value form -- an
    # absolute value redacted like a request URL, a relative one with its path kept and a
    # `?***` for a query, a value the parser rejects by string surgery, and OBS-11's placeholder
    # for a userinfo on every one of those routes (P5-100); never OBS-15's sentinel, because a
    # warning naming `[malformed url]` names nothing -- reached through the policy's first
    # URL-valued header name, since that entry point is keyed by header name (OBS-16, OBS-17).
    # Then CFG-24's grammar rule, for the credential the redactor cannot know is one.
    def shown(url)
      scrubbed = scrub_userinfo(url)
      redacted = Instrumentation::Redactor::DEFAULT.header_value(SHOWN_AS, scrubbed)
      redacted.gsub(CREDENTIAL_BEFORE_AT, "#{Instrumentation::Redactor::REDACTED_USERINFO}@")
    end

    # CFG-24's grammar applied to the RAW value, before the parser or the redactor can split a
    # password at a `/`, `?` or `#` it contains: in a proxy URL everything from the authority's
    # start through the LAST `@` is userinfo, so it is replaced whole. The belt above runs on the
    # redactor's output and stops at the first reserved character, which left the prefix of a
    # password such as `pa/ss`, `p#ss` or `se#cret` in the warning (phase 10's review round 0,
    # R0-4); this pass runs first and has no delimiter to stop at. A value with no `@` is
    # returned unchanged.
    def scrub_userinfo(url)
      last = url.rindex("@")
      return url if last.nil?

      start = AUTHORITY_START.match(url)&.end(0) || 0
      return url if start > last

      "#{url[0, start]}#{Instrumentation::Redactor::REDACTED_USERINFO}@#{url[(last + 1)..]}"
    end

    def url_problem(host, raw_port)
      return "has no explicit port; CFG-25 forbids defaulting to 80 or 443" if raw_port.nil?
      return "has a port outside 0..65535" if parse_port(raw_port).nil?

      "has no host" if host.nil? || host.empty?
    end

    # Resolved at call time, not into a frozen table at load time: this file must not name
    # Proxy::Type at require time, because it loads from inside `class Proxy`'s body before the
    # nested types do. `downcase` with no argument (Dexpace/NoLocaleCaseFold).
    def scheme_type(scheme)
      case scheme.to_s.downcase
      when "socks5" then Proxy::Type::SOCKS5
      when "socks4" then Proxy::Type::SOCKS4
      else Proxy::Type::HTTP
      end
    end

    # Userinfo arrives percent-encoded and split() does not decode it. URI.decode_uri_component
    # and never RFC3986_PARSER.unescape, which prints an obsolescence warning on 3.4.10 against a
    # gate set that fails on warnings; and never decode_www_form_component, which turns a "+" in
    # a password into a space.
    def credentials(userinfo)
      user, password = userinfo.to_s.split(":", 2)
      [user, password].map do |part|
        part.nil? || part.empty? ? nil : ::URI.decode_uri_component(part)
      end
    end

    # CFG-26: the system property (pipe-separated) wins over the environment variable
    # (comma-separated), and the winner does not depend on which source supplied the host -- a
    # proxy resolved from HTTPS_PROXY still honours http.nonProxyHosts.
    def non_proxy_hosts(configuration)
      raw = configuration.raw_property(NON_PROXY_PROP)
      return split_non_proxy(raw, "|") unless raw.nil? || raw.empty?

      split_non_proxy(configuration.string(Configuration::Keys::NO_PROXY), ",")
    end

    # Base 10 explicit, and the 0..65535 range check is this resolver's: the parser accepts
    # "http://h:70000" with no complaint. Kernel.Integer and never ::Integer(...), which is a
    # constant reference.
    def parse_port(raw)
      value = ::Kernel.Integer(raw.to_s.strip, 10, exception: false)
      value.nil? || value.negative? || value > 65_535 ? nil : value
    end

    # CFG-26's observable order, in this order: split on an unescaped separator -> drop empty
    # fragments (BEFORE unescape and trim) -> unescape -> trim. Verified against the chapter's own
    # conformance outputs: "a\|b|c" -> ["a|b", "c"], "a\,b,c" -> ["a,b", "c"], "a||c" -> ["a", "c"],
    # "a| |c" -> ["a", "", "c"]. The -1 limit is NOT load-bearing -- the very next step drops empty
    # fields anyway -- and stays because it makes this the literal `split` half of CFG-26's order
    # rather than a pre-filtered one. A whitespace-only fragment survives that order as an EMPTY
    # token, and an empty glob is not a host pattern, so it is dropped after the order the
    # requirement fixes has been observed.
    #
    # CFG-27: exactly one bare "*" is bypass-all, carried by the flag and never by a literal
    # entry; a "*" inside a multi-entry list stays a normal any-host glob, which is why this
    # compares the whole token list and not `tokens.include?("*")`.
    #
    # @return [Array] the HostPattern list and CFG-27's bypass-all flag
    def split_non_proxy(raw, separator)
      tokens = tokens_of(raw.to_s, separator)
      return [[], true] if tokens == ["*"]

      [tokens.reject(&:empty?).map { |token| Proxy::HostPattern.of(token) }, false]
    end

    def tokens_of(raw, separator)
      pattern = ::Regexp.new("(?<!\\\\)#{::Regexp.escape(separator)}", timeout: 1.0)
      fragments = raw.split(pattern, -1).reject(&:empty?)
      fragments.map { |token| token.gsub("\\#{separator}", separator).strip }
    end

    # P5-8, discharged by phase 5b: Kernel#warn, following phase 2's P2-6 verbatim, and an
    # `http.instrumentation.config` event BESIDE it -- CFG-24's and CFG-25's "warning log"
    # through §8.1's facade -- with neither removed. The emission is contained (OBS-20), so a
    # raising sink cannot turn a warning into a failure. Always nil, so a caller can
    # `return warn_and_nil(...)`.
    def warn_and_nil(message, logger)
      ::Kernel.warn("[dexpace] #{message}")
      Instrumentation.diagnostic(logger, event: Instrumentation::Events::INSTRUMENTATION_CONFIG,
                                         message: message,)
    end
  end

  private_constant :ProxyResolution
end
