# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# This file names no Dexpace::Serde constant and never calls require "json"; a whole JSON
# document may still travel on one data line. ::JSON is not read here either.
module Dexpace
  module SSE
    # @return [String] a comment mentioning Serde and JSON is not a dependency
    def self.note = "commented"
  end
end
