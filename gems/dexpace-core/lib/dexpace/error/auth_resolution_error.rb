# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # AUTH-6's second failure: the selected descriptor lists no scheme the caller can supply a
  # credential for. Distinct from Dexpace::InvalidArgumentError, which is AUTH-6's FIRST failure
  # (no descriptor at any tier): a caller who passed a descriptor passed nothing invalid, and one
  # who cannot tell "you gave me nothing" from "you gave me something I cannot satisfy" cannot
  # act on either. Carries the required schemes in preference order and the available ones as
  # members, so a caller reads them rather than parsing the message. Flat under Dexpace, in
  # phase 2's shape (`< ::StandardError` with the Dexpace::Error marker included), because the
  # condition is a general resolution failure and not one only the Auth subsystem can raise.
  class AuthResolutionError < ::StandardError
    include Dexpace::Error

    # @return [Array<Dexpace::Auth::Scheme>] the descriptor's schemes, in preference order
    attr_reader :required
    # @return [Array<Dexpace::Auth::Scheme>] the schemes the caller said it could supply
    attr_reader :available

    # @param required [Array<Dexpace::Auth::Scheme>]
    # @param available [Array<Dexpace::Auth::Scheme>]
    def initialize(required:, available:)
      @required = required.dup.freeze
      @available = available.dup.freeze
      super("no satisfiable auth scheme: required #{names(@required)} in preference order, " \
            "available #{names(@available)} (AUTH-6)")
    end

    private

    def names(schemes)
      schemes.empty? ? "(none)" : schemes.map(&:name).join(", ")
    end
  end
end
