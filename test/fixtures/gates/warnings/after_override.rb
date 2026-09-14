# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../support/dexpace_test_case"

# A method redefined AFTER the shared test case has installed its Warning.warn override. Under
# `ruby -w` the warning is raised as an error, with the file and line, by the override itself.
class RedefinedAfterOverride
  def call = 1
  def call = 2
end

RedefinedAfterOverride.new.call
