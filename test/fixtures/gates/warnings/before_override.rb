# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A method redefined at load time, BEFORE the shared test case -- and its Warning.warn override
# -- has been required. Under `ruby -w` this warns on stderr and the process exits 0, which is
# exactly the case the override cannot catch and the stderr scan in tools/suite_runner.rb exists
# for.
class RedefinedBeforeOverride
  def call = 1
  def call = 2
end

RedefinedBeforeOverride.new.call

require_relative "../../../support/dexpace_test_case"
