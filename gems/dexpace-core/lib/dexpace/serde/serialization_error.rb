# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error"

module Dexpace
  module Serde
    # The encode half of SEAM-20's failure contract: a codec that cannot serialise a value raises
    # this, from inside the rescue of whatever its backing library raised, so Ruby chains the
    # original as #cause rather than leaking the library's exception type (serde/5821286d).
    class SerializationError < Error
    end
  end
end
