# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "json/version"

module Dexpace
  # Wire codecs: the serde seam's shipped implementations. The seam contract itself lives in
  # dexpace-core.
  module Serde
    # The reference wire codec, over Ruby's `json` default gem. Phase 0 ships the namespace and
    # VERSION only; the codec itself lands in phase 7.
    #
    # CAUTION: this module shadows ::JSON inside its own namespace. An unqualified `JSON.parse`
    # written anywhere under `Dexpace::Serde::JSON` resolves to this module, not to Ruby's, and
    # fails with a confusing NoMethodError. Every reference to Ruby's JSON from inside here is
    # written `::JSON`.
    module JSON
    end
  end
end
