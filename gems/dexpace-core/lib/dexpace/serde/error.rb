# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  module Serde
    # The root of the seam's SDK-owned failure hierarchy (SEAM-23).
    #
    # A class, where phase 1 made the SDK-wide Dexpace::Error a module. The inversion is deliberate
    # and the rule for every later phase is: the SDK root is a module, a seam-local root with no
    # competing Ruby family is a class. Phase 1's root is a module because XCUT-4 requires transport
    # errors to belong to Ruby's IOError family and single inheritance makes a class root and that
    # requirement mutually exclusive. Nothing competes here: SEAM-20 and SEAM-21 both say a genuine
    # stream I/O error propagates unwrapped rather than being reclassified as a serde failure, so a
    # serde error is never also an IOError. SEAM-23 asks in so many words for "a stable, SDK-owned
    # hierarchy (a base serde failure with encode/decode subtypes)" that is "open for
    # codegen/adapters to add more specific subtypes", and a class root delivers that literally.
    #
    # Including Dexpace::Error keeps `rescue Dexpace::Error` catching it. Inside this namespace a
    # bare `Error` is this class, so core writes the SDK root as Dexpace::Error everywhere.
    class Error < ::StandardError
      include Dexpace::Error
    end
  end
end
