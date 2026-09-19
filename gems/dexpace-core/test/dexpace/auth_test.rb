# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../../lib/dexpace/auth"

# Exercises: AUTH-8 -- the namespace file: the one redaction marker every credential renders.
class DexpaceAuthTest < DexpaceTestCase
  test "the namespace exists with the one shared redaction marker, frozen" do
    assert_kind_of(Module, Dexpace::Auth)
    assert_equal("[REDACTED]", Dexpace::Auth::REDACTED)
    assert_predicate(Dexpace::Auth::REDACTED, :frozen?)
  end

  test "the namespace file adds no constant but the marker" do
    assert_equal([:REDACTED], Dexpace::Auth.constants(false) & [:REDACTED])
  end
end
