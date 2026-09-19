# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  module Redirect
    # REDIR-15's "fail with a clear error": the redirect step refused to follow an HTTPS -> HTTP
    # hop because the caller did not opt in with `allow_scheme_downgrade: true`. Raised by
    # Step after the current response is closed (REDIR-22b) and after the rejection is emitted
    # (Events::SCHEME_DOWNGRADE_REJECTED); never by Location or Origin. The message names the
    # two AUTHORITIES -- scheme, host, and the port when it is not the scheme's default -- and
    # not the full URLs: a path or a query is where a token travels, and an exception's message
    # is a diagnostic representation a sink will render (XCUT-19).
    class SchemeDowngradeError < ::StandardError
      include Dexpace::Error

      # @param from [URI::Generic] the current hop's request URL
      # @param to [URI::Generic] the resolved target
      def initialize(from:, to:)
        super("redirect from #{authority(from)} to #{authority(to)} would downgrade HTTPS to " \
              "HTTP and is refused by default; opt in with allow_scheme_downgrade: true " \
              "(REDIR-15)")
      end

      private

      def authority(uri)
        port = uri.port
        rendered = "#{uri.scheme}://#{uri.host}"
        port.nil? || port == uri.default_port ? rendered : "#{rendered}:#{port}"
      end
    end
  end
end
