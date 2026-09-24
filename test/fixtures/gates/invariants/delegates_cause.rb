# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The positive control: this file delegates to the single walk and names `.cause` only in prose
# and in a requirement ID. A grep would report all three lines; the AST reports none.
#
# XCUT-9: "any classification that walks an error's cause chain MUST be cycle-safe". The walk
# lives in Dexpace.each_cause and nowhere else, so a classifier reads the chain through it.
module Delegates
  # Walks the cause chain -- through the one walk, never by reading #cause here.
  def self.retryable?(error)
    ::Dexpace.each_cause(error).any? { |one| one.respond_to?(:retryable?) && one.retryable? }
  end

  def self.prose = "read the cause chain through Dexpace.each_cause, never error.cause"
end
