# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# IO-4, IO-9, IO-17, IO-28, and BODY-13's one-helper rule.
class DexpaceStreamErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::StreamError, "boom"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::StreamError, caught)
  end

  # IO-4, IO-17 and IO-42 each literally say "an I/O error", and ::IOError is Ruby's root for that
  # family, so an existing `rescue IOError` site keeps matching.
  test "is in Ruby's IOError family" do
    assert_operator(Dexpace::StreamError, :<, ::IOError)
  end

  # NOT because of XCUT-4: XCUT-4 makes a transport error report itself as always-retryable, and a
  # stream-contract violation must not claim that. StreamError is a sibling of phase 8's
  # TransportError inside ::IOError, never a subclass, so this stays true when phase 8 lands.
  test "is not an EOF error, so a contract violation is never read as end of stream" do
    refute_operator(Dexpace::StreamError, :<, ::EOFError)
  end

  # BODY-13 requires the short-transfer message form of BODY-10/HTTP-39 and the zero-read form of
  # BODY-25 to come from ONE helper "so the message form cannot diverge". 3b calls these.
  test "short_transfer builds the one message form for a short transfer" do
    error = Dexpace::StreamError.short_transfer(transferred: 3, expected: 10)

    assert_instance_of(Dexpace::StreamError, error)
    assert_includes(error.message, "3")
    assert_includes(error.message, "10")
  end

  test "zero_read builds the one message form for IO-17's source-contract violation" do
    error = Dexpace::StreamError.zero_read(requested: 4096)

    assert_instance_of(Dexpace::StreamError, error)
    assert_includes(error.message, "4096")
    assert_includes(error.message, "IO-17")
  end

  # The two helpers build and return; they do not raise. A caller writes `raise` in front of them,
  # which is what keeps the raise site -- and its backtrace -- at the violation.
  test "the helpers return an unraised error" do
    assert_nil(Dexpace::StreamError.short_transfer(transferred: 0, expected: 1).backtrace)
    assert_nil(Dexpace::StreamError.zero_read(requested: 1).backtrace)
  end
end
