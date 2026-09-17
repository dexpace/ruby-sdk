# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Instrumentation
    # OBS-12, OBS-17 and OBS-18: what the redactor keeps and what it scrubs -- the query
    # parameter names whose values pass, the header names whose values are logged at all, the
    # header names whose values are URLs, and whether a non-allow-listed header is emitted with
    # the fixed marker or omitted. A frozen Data of three folded Sets and one boolean, built
    # through the validating `.build` and derived through Model#with (never Data#with, which
    # skips this initialize on the 3.2 floor).
    #
    # It has NO member that can reach userinfo, deliberately (boundary 4, XCUT-19(a)): OBS-11's
    # redaction is "unconditional and independent of any allow-list", and a policy with no
    # keyword, field or configuration key for it is the only reading a policy object can honour.
    # Every name is folded once here with a locale-free downcase (Dexpace/NoLocaleCaseFold), so
    # the redactor compares folded against folded and writes no second fold.
    class RedactionPolicy < Data.define(:query_allow_list, :header_allow_list, :url_header_names,
                                        :omit_disallowed_headers,)
      include Model

      private_class_method :new

      # OBS-12: "exactly {api-version}".
      DEFAULT_QUERY_ALLOW_LIST = ::Set["api-version"].freeze
      private_constant :DEFAULT_QUERY_ALLOW_LIST

      # OBS-17: "at minimum Location and Content-Location".
      DEFAULT_URL_HEADER_NAMES = ::Set["location", "content-location"].freeze
      private_constant :DEFAULT_URL_HEADER_NAMES

      # OBS-18: "only diagnostic, non-credential headers". Twenty-six names, chosen rather than
      # derived (P5-30) and NFR-4-locked through DEFAULT. Absent on purpose: authorization and
      # proxy-authorization (the credential), cookie and set-cookie (a session), x-api-key and
      # every vendor variant (a key a default-deny list could not enumerate anyway), and the two
      # challenge headers www-authenticate and proxy-authenticate -- a Digest challenge carries a
      # server nonce, and whether that is loggable is AUTH's question, phase 6's. Default-deny
      # means an omission is safe and an inclusion is not, so the list errs short.
      DEFAULT_HEADER_ALLOW_LIST = ::Set[
        "accept", "accept-encoding", "cache-control", "connection", "content-encoding",
        "content-length", "content-location", "content-type", "date", "etag", "expires",
        "if-match", "if-modified-since", "if-none-match", "if-unmodified-since",
        "last-modified", "location", "retry-after", "server", "traceparent", "tracestate",
        "user-agent", "vary", "via", "x-correlation-id", "x-request-id",
      ].freeze
      private_constant :DEFAULT_HEADER_ALLOW_LIST

      # Builds a policy, folding each list into a frozen Set of lower-case names. A list may be
      # any Enumerable of Strings or Symbols; an empty query allow-list is a real value that
      # redacts every parameter (OBS-12's "An empty allow-list MUST redact every value"), which
      # is why no list keyword treats nil as "use the default".
      #
      # @param query_allow_list [Enumerable<String, Symbol>] OBS-12's parameter names
      # @param header_allow_list [Enumerable<String, Symbol>] OBS-18's header names
      # @param url_header_names [Enumerable<String, Symbol>] OBS-17's URL-valued header names
      # @param omit_disallowed_headers [Boolean] OBS-18's mode: true omits a non-allow-listed
      #   header, false (the default, P5-35) emits it with the fixed REDACTED marker, because a
      #   header that was present and redacted and one that was absent are different facts
      # @return [RedactionPolicy] frozen
      # @raise [Dexpace::InvalidArgumentError] when a list is not an Enumerable of names
      def self.build(query_allow_list: DEFAULT_QUERY_ALLOW_LIST,
                     header_allow_list: DEFAULT_HEADER_ALLOW_LIST,
                     url_header_names: DEFAULT_URL_HEADER_NAMES,
                     omit_disallowed_headers: false)
        new(query_allow_list: query_allow_list, header_allow_list: header_allow_list,
            url_header_names: url_header_names, omit_disallowed_headers: omit_disallowed_headers,)
      end

      # Validates and folds; reached only through .build and Model#with.
      def initialize(query_allow_list:, header_allow_list:, url_header_names:,
                     omit_disallowed_headers:)
        super(
          query_allow_list: fold_set("query_allow_list", query_allow_list),
          header_allow_list: fold_set("header_allow_list", header_allow_list),
          url_header_names: fold_set("url_header_names", url_header_names),
          omit_disallowed_headers: omit_disallowed_headers ? true : false,
        )
      end

      # One frozen Set of folded names. Each element must be a String or a Symbol; the fold is
      # `downcase` with no argument, the repository's one case fold. Private, and defined before
      # DEFAULT below because the class body runs top to bottom and .build runs the initializer.
      def fold_set(member, names)
        unless names.respond_to?(:each) && !names.is_a?(::String)
          raise InvalidArgumentError, "#{member} must be a list of names, got #{names.class}"
        end

        folded = ::Set.new #: Set[String]
        names.each do |name|
          unless name.is_a?(::String) || name.is_a?(::Symbol)
            raise InvalidArgumentError, "#{member} holds #{name.inspect}, which is not a name"
          end

          folded << Model.frozen_string(name.to_s.downcase)
        end
        folded.freeze
      end
      private :fold_set

      # The policy every redactor built without one uses: OBS-12's, OBS-17's and OBS-18's
      # defaults with the marker mode. `Set` needs no require: Ruby 3.2, the floor, autoloads it,
      # and the cop set refuses the redundant require.
      DEFAULT = build
    end
  end
end
