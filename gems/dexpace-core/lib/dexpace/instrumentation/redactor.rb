# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "redaction_policy"

module Dexpace
  module Instrumentation
    # OBS-11 through OBS-18, XCUT-19 and XCUT-20: the URL and header-value redactor, the port's
    # security surface. Two public entry points with two failure policies (P5-25), because OBS-15
    # and OBS-16 give OPPOSITE answers to one unparseable input: URL redaction returns the fixed
    # `[malformed url]` sentinel, while a URL arriving as a header value keeps its path and
    # appends `?***`, since a Location a reader cannot see the path of is a useless log line.
    # One entry point loses one requirement whichever way the collision resolves.
    #
    # Every parse is `URI::RFC3986_PARSER.split`, pinned (Dexpace/NoUriDefaultParser), and the
    # redacted form is REASSEMBLED from the nine raw components it returns rather than written
    # back through the URI setters and `#to_s` (P5-91): `URI#to_s` drops a port equal to the
    # scheme's default, so `http://h:80/` would come back as `http://h/`, which OBS-14's "MUST NOT
    # alter scheme, host, port, or path" forbids -- and the raw port is readable only from
    # `split`, because `#port` is already 80 by the time it is read (5a's resolver found the same).
    # Reassembly also makes the opaque-URI raise -- `userinfo=` and `query=` on `mailto:`, `urn:`
    # and `data:` -- unreachable by construction rather than by guard: nothing absent is ever
    # written, which is P5-27's rule with no setter left to apply it to.
    #
    # The decoder is `URI.decode_www_form_component`, never `URI::RFC3986_PARSER.unescape`, which
    # warns on 3.4.10. The rescue is `StandardError`, not `URI::Error` (P5-26): the parser
    # ACCEPTS `%FF` in a query, decoding it yields invalid UTF-8, and `String#downcase` on that
    # raises an ArgumentError that is not under URI::Error -- reachable from any server. The
    # common case never reaches the rescue, because the name is folded through `#scrub` first;
    # the rescue is the totality backstop XCUT-20 asks for.
    #
    # Frozen, holding a frozen policy, with every intermediate a method local: XCUT-11's shared
    # instance by construction. Redactor::DEFAULT is the one over RedactionPolicy::DEFAULT.
    class Redactor
      # OBS-15's fixed sentinel for a URL that cannot be parsed or rebuilt.
      MALFORMED_URL = "[malformed url]"
      # OBS-12's and OBS-13's replacement for a redacted value.
      REDACTED_VALUE = "***"
      # OBS-11's placeholder, rendered by URI as `***:***@`.
      REDACTED_USERINFO = "***:***"
      # OBS-18's fixed marker for a header whose name is not allow-listed.
      REDACTED_HEADER = "REDACTED"
      # OBS-16's marker for a relative or unparseable header value that carried a query or a
      # fragment.
      RELATIVE_MARKER = "?***"

      private_class_method :new

      # The policy this redactor answers from; public so a later phase derives one with
      # RedactionPolicy#with rather than rebuilding, which is what keeps OBS-17's "shared ... so
      # it cannot drift" true when phase 6 needs one more allow-listed header.
      #
      # @return [RedactionPolicy]
      attr_reader :policy

      # Builds a frozen redactor over a policy.
      #
      # @param policy [RedactionPolicy] the sets and the mode; RedactionPolicy::DEFAULT when
      #   omitted
      # @return [Redactor] frozen
      # @raise [Dexpace::InvalidArgumentError] without a policy
      def self.build(policy: RedactionPolicy::DEFAULT)
        Model.required!("policy", policy)
        new(policy).freeze
      end

      # Defined before DEFAULT is assigned: the class body runs top to bottom.
      def initialize(policy)
        @policy = policy
      end

      # OBS-11 through OBS-15: the redacted form of a URL, or MALFORMED_URL. Userinfo becomes
      # `***:***@` whenever present, whatever the policy says (OBS-11, XCUT-19(a)); each query
      # value becomes `***` unless its decoded, folded name is allow-listed, all values of one
      # name taking the same branch because the decision is a function of the name alone
      # (OBS-12); a fragment's `key=value` tokens follow the same rule and a fragment with no `=`
      # is kept verbatim (OBS-13); scheme, host, port and path are written back byte for byte, a
      # present-but-empty query keeps its trailing `?`, and a `?` inside the fragment is the
      # parser's to keep there (OBS-14). Total: any failure yields the sentinel (OBS-15).
      #
      # @param value [String, URI::Generic, nil] the URL
      # @return [String] the redacted URL, or MALFORMED_URL
      def url(value)
        return MALFORMED_URL if value.nil?

        components = split(value.to_s)
        reassemble(components[0], components[1], components[2], components[3], components[4],
                   components[5], components[6], components[7], components[8],)
      rescue ::StandardError
        MALFORMED_URL
      end

      # OBS-16 and OBS-17: the value a header is logged with. A header whose folded name is not
      # one of the policy's URL-valued names passes through unchanged (OBS-17); a URL-valued
      # header's parseable absolute value is redacted exactly like a request URL, a relative
      # value keeps its path and drops everything after it behind `?***` whenever it carried a
      # query or a fragment, and an unparseable value gets the same treatment by string surgery
      # on the raw value (OBS-16, P5-28). Returns a String ALWAYS -- a nil value returns "" --
      # which is the one place api-design/6ea28c9c's "never nil for absent" is overruled by
      # requirement: OBS-16's output is a header value, and nil is not one. Never returns
      # MALFORMED_URL (P5-25).
      #
      # @param name [String, Symbol, nil] the header name, in any casing
      # @param value [String, nil] the header value
      # @return [String]
      def header_value(name, value)
        return "" if value.nil?

        raw = value.to_s
        return raw unless @policy.url_header_names.include?(fold(name))

        redact_header_url(raw)
      rescue ::StandardError
        RELATIVE_MARKER
      end

      # OBS-18's gate: whether a header's value is logged at all, against the folded allow-list.
      #
      # @param name [String, Symbol, nil] the header name, in any casing
      # @return [Boolean]
      def header_name?(name)
        return false if name.nil?

        @policy.header_allow_list.include?(fold(name))
      end

      # The redactor over RedactionPolicy::DEFAULT: the one every event and step uses unless
      # handed another.
      DEFAULT = build

      private

      # The pinned parser's nine raw components -- scheme, userinfo, host, port, registry (never
      # set by this parser), path, opaque, query and fragment -- each nil when absent and
      # otherwise exactly the bytes the input carried. rbs's stdlib signatures do not declare
      # RFC3986_Parser#split, hence the untyped constant (5a's resolver does the same).
      #
      # @raise [URI::InvalidURIError] for a value the parser rejects
      def split(value)
        parser = ::URI::RFC3986_PARSER #: untyped
        parser.split(value)
      end

      # The redacted URL from the nine raw components. Every component is written back exactly
      # as split returned it except the three OBS-11..OBS-13 redact, and only when present: a
      # present-but-empty query keeps its `?` (OBS-14), an absent one gets none. Nine positionals
      # is what the parser hands back, hence the ParameterLists disable.
      #
      # rubocop:disable-next Metrics/ParameterLists
      def reassemble(scheme, userinfo, host, port, _registry, path, opaque, query, fragment)
        out = +""
        out << scheme << ":" unless scheme.nil?
        out << authority(userinfo, host, port) unless host.nil?
        out << (opaque || path || "")
        out << tail(query, fragment)
      end

      # The query and the fragment, each redacted and each present iff it was.
      def tail(query, fragment)
        out = +""
        out << "?" << redact_pairs(query, keep_bare: true) unless query.nil?
        out << "#" << redact_pairs(fragment, keep_bare: false) unless fragment.nil?
        out
      end

      # `//` is emitted iff there was an authority, which split reports as a non-nil host (`""`
      # for `file:///`); the userinfo, when present, is OBS-11's placeholder and never the input.
      def authority(userinfo, host, port)
        out = +"//"
        out << REDACTED_USERINFO << "@" unless userinfo.nil?
        out << host
        out << ":" << port unless port.nil?
        out
      end

      # OBS-16's three routes over two objects (P5-28): a value with a scheme delegates to #url
      # (falling through to the surgery form if that yielded the sentinel, P5-25); a relative
      # value keeps its split path and gets the marker iff it carried a query or a fragment, the
      # presence test being `!nil?` because `/cb?` splits with an EMPTY query and an empty query
      # is a query; and a value the parser rejects has no components to read, so the path is the
      # raw value up to the first `?` or `#`.
      def redact_header_url(raw)
        scheme, _userinfo, _host, _port, _registry, path, _opaque, query, fragment = split(raw)
        if scheme.nil?
          carried = !(query.nil? && fragment.nil?)
          carried ? "#{path}#{RELATIVE_MARKER}" : raw
        else
          redacted = url(raw)
          redacted.equal?(MALFORMED_URL) ? surgery(raw) : redacted
        end
      rescue ::URI::InvalidURIError
        surgery(raw)
      end

      # The unparseable route: the raw value up to the first `?` or `#`, then the marker if
      # there was one.
      def surgery(raw)
        cut = [raw.index("?"), raw.index("#")].compact.min
        cut.nil? ? raw : "#{raw[0, cut]}#{RELATIVE_MARKER}"
      end

      # OBS-12 and OBS-13 over one `&`-separated string. Each pair splits on its FIRST `=`; the
      # name is decoded, scrubbed and folded, and the value kept iff the folded name is in the
      # allow-list. A token with no `=` is kept verbatim. Trailing empty pairs -- a trailing `&`
      # -- are dropped, which OBS-14 permits ("MAY be dropped"); interior empties are kept so the
      # rest of the string is untouched. For a fragment (`keep_bare: false`) a string with no
      # `=` anywhere is returned verbatim, OBS-13's "plain fragment".
      def redact_pairs(string, keep_bare:)
        return string if !keep_bare && !string.include?("=")

        pairs = string.split("&", -1)
        pairs.pop while pairs.length > 1 && pairs.last.empty?
        pairs.map { |pair| redact_pair(pair) }.join("&")
      end

      def redact_pair(pair)
        name, separator, value = pair.partition("=")
        return pair if separator.empty?

        decoded = ::URI.decode_www_form_component(name)
        kept = @policy.query_allow_list.include?(fold(decoded))
        "#{name}=#{kept ? value : REDACTED_VALUE}"
      end

      # The one fold in this file: `#scrub` first so an invalid-UTF-8 name cannot raise out of
      # the case fold (verified fact 7), then `downcase` with no argument.
      def fold(name)
        name.to_s.scrub("").downcase
      end
    end
  end
end
