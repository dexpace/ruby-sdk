# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../support/dexpace_test_case"

# The positive control: a suite that warns nowhere passes the runner, so a runner that rejected
# everything would fail here.
class CleanFixtureTest < DexpaceTestCase
  test "one assertion, no warning" do
    assert_equal(2, 1 + 1)
  end
end
