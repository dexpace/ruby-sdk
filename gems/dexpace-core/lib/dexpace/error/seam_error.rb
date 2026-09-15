# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised when a seam is in a state the caller has to fix but did not pass in: no provider is
  # registered, more than one is (SEAM-5), or an adapter was built against an incompatible
  # dexpace-core (design §2.3's version-skew guard).
  #
  # Deliberately not an ArgumentError. `error-handling/5a185ba9` asks for a standard-library
  # exception where one exactly fits, and ArgumentError exactly fits a bad argument -- which is
  # what Dexpace::InvalidArgumentError is for, and is what a conflicting install raises. Nothing
  # was wrong with the argument here; the process is missing a provider.
  class SeamError < ::StandardError
    include Dexpace::Error
  end
end
