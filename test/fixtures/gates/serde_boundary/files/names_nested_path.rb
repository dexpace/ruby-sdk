# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module SSE
    def self.codec = Dexpace::Serde::JSON::Codec.new
  end
end
