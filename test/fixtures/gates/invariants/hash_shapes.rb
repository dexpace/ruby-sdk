# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Every Hash-valued instance-variable shape, decidable and not.
module Bad
  class Store
    def initialize(seed)
      @a = {}
      @b = Hash.new(0)
      @c = ::Hash.new
      @d = {}.compare_by_identity
      @e = build_map   # undecidable: the stated gap
      @f = seed        # undecidable: the stated gap
      @cap = 1024      # not a Hash; must NOT be reported
      @name = "store"  # not a Hash; must NOT be reported
    end

    def lazily
      @g ||= {}        # decidable through OP_ASGN_OR
    end

    def build_map = {}
  end
end
