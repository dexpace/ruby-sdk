# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Prism returns its diagnostics on the result and never routes them through Warning.warn, so a
# Prism parse is not the hazard the gate exists for and must not be reported.
module PrismOnly
  def self.scan(path) = Prism.parse_file(path)
end
