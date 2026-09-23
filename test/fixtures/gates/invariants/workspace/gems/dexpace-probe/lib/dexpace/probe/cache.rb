# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Deliberately non-conforming, in a gem that is not core: an instance-lived Hash keyed by whatever
# a caller hands it, which is the shape XCUT-14 reserves for Dexpace::BoundedMap. In a gem OTHER
# than core so the fixture also proves the bounded_map scan reaches every gem's lib/ while
# seam_names reaches core's alone.
module Dexpace
  module Probe
    class Cache
      def initialize
        @by_origin = {}
      end

      def store(origin, value)
        @by_origin[origin] = value
      end
    end
  end
end
