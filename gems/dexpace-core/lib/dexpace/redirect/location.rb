# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"

require_relative "../http/url"

module Dexpace
  module Redirect
    # Turns a Location header value into a dispatchable, credential-free, frozen target, or
    # raises the bare ::URI::InvalidURIError for Step to convert BY CLASS at the one call site
    # that also logs the raw value (R7). Never Dexpace::URL.parse!, which rejects a relative
    # reference (HTTP-47) and REDIR-14 requires resolving one; and never URI.join, which the
    # Dexpace/NoUriDefaultParser cop refuses (url-and-query-encoding/08c54234): one call to
    # URI::RFC3986_PARSER.join resolves a relative reference against the current hop and takes
    # an absolute one as-is (REDIR-14), preserving already-percent-encoded octets, a bracketed
    # IPv6 host and a non-default port byte for byte (REDIR-13; verified fact 2). What it does
    # NOT do is refuse a target this client cannot dispatch -- join hands back a URI::MailTo, a
    # URI::FTP, a URI::Generic for `javascript:`, or an http URL with no host at all
    # (`http:foo`, `http:///p`) -- so the scheme and the host are screened here, and REDIR-18's
    # third trigger, "an unsupported/unknown scheme", is implemented rather than discovered as a
    # NoMethodError on a nil host inside Origin.
    #
    # The userinfo strip is spelled `userinfo = ""` and NEVER `userinfo = nil`, which is a silent
    # no-op that forwards the server-supplied credential (REDIR-12; redirect-handling/b42d265d,
    # verified fact 1 on every row). It runs AFTER the screen, because on an opaque URI the
    # writer raises, and BEFORE the freeze, because on a frozen one it raises FrozenError. The
    # result is what the loop's visited check, the origin comparison, the log record and the
    # follow-up request all see: one resolution per hop, one object.
    #
    # This module never inspects the exception's #message -- it differs by one space between
    # uri 0.13.3 and 1.x -- and neither may any caller or test (url-and-query-encoding/08c54234).
    # A private_constant, asserted at Step's call sites, with a sig/ mirror because the strict
    # `core` Steep target types every file under lib/.
    module Location
      extend self

      # The schemes this client dispatches; anything else is REDIR-18's unsupported scheme.
      SUPPORTED_SCHEMES = %w[http https].freeze

      # @param current_url [URI::Generic] the current hop's request URL, always absolute
      # @param header_value [String] the raw Location value, absolute or relative, non-empty
      # @return [URI::Generic] absolute, http or https, with a host, userinfo-stripped, frozen
      # @raise [::URI::InvalidURIError] on a malformed reference (join's own), or on a resolved
      #   target with an unsupported scheme or no host (REDIR-18, all three triggers, one class)
      def resolve(current_url, header_value)
        parser = ::URI::RFC3986_PARSER #: untyped
        target = parser.join(URL.external_form(current_url), header_value) #: URI::Generic
        unless dispatchable?(target)
          raise ::URI::InvalidURIError, "redirect target has an unsupported scheme or no host"
        end

        target.userinfo = "" # REDIR-12: "" clears user AND password; nil is a no-op
        target.freeze
      end

      private

      def dispatchable?(target)
        scheme = target.scheme
        host = target.host
        !scheme.nil? && SUPPORTED_SCHEMES.include?(scheme.downcase) && !host.nil? && !host.empty?
      end
    end
    private_constant :Location
  end
end
