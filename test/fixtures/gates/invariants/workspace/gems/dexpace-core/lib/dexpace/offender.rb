# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Deliberately non-conforming, in core's own tree: a second cause walk (XCUT-9) and a reference to
# a concrete adapter namespace (SEAM-2). Both must be reported when the gates run against this
# workspace.
module Dexpace
  module Offender
    def self.root(error)
      error.cause
    end

    def self.codec
      Dexpace::Serde::JSON::Codec
    end
  end
end
