# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # This gem's own version.
  #
  # The literal lives here rather than being read from the repository root, because a
  # built .gem does not ship the repository and NFR-15 requires a runtime-emitted
  # identifier -- the User-Agent -- to report a real version rather than an "unknown"
  # placeholder. VERSIONS at the repository root is NFR-14's single source of truth, and
  # `rake gates:versions` asserts the two agree.
  VERSION = "0.0.0"
end
