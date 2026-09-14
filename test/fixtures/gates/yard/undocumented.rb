# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a public method with no YARD block (styleguide 14.1).
module UndocumentedFixture
  def self.no_yard_block
    :nothing
  end
end
