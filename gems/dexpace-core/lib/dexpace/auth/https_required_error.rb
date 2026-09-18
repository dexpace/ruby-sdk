# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../error"

module Dexpace
  module Auth
    # AUTH-28: the AUTH step refused to attach a credential to a request whose URL scheme is
    # not `https`. Raised BEFORE any token fetch or header write, and only on a path where a
    # credential would be attached -- a cross-origin redirect re-issue skips the guard (AUTH-29)
    # because nothing is attached there. The message names the concrete step and the offending
    # scheme, as the requirement asks; both are members too.
    class HTTPSRequiredError < ::StandardError
      include Dexpace::Error

      # @return [String] the request URL's scheme, as parsed
      attr_reader :scheme
      # @return [String] the concrete step's class name
      attr_reader :step

      # @param scheme [String]
      # @param step [String]
      def initialize(scheme:, step:)
        @scheme = scheme
        @step = step
        super("#{step} refuses to attach a credential to a #{scheme.inspect} request: " \
              "credentials are stamped over HTTPS only (AUTH-28)")
      end
    end
  end
end
