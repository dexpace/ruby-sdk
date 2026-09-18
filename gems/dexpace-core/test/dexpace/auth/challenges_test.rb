# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/challenges"
require_relative "../../support/challenge_fixtures"

# Exercises: AUTH-12, AUTH-13 -- the RFC 7235 challenge parser: every clause of the two
# requirements, the grammar's parameter-versus-challenge ambiguity, the recovery clauses on the
# deliberately malformed fixtures, and the bounded-time measurement that discharges the
# no-regexp house rule by measurement rather than by claim.
class DexpaceAuthChallengesTest < DexpaceTestCase
  Challenges = Dexpace::Auth::Challenges

  def shapes(value)
    Challenges.parse(value).map { |c| [c.scheme, c.params] }
  end

  test "AUTH-13: nil, empty and blank input yield an empty list" do
    assert_empty(Challenges.parse(nil))
    assert_empty(Challenges.parse(""))
    assert_empty(Challenges.parse("   "))
    assert_empty(Challenges.parse(" , ,\t"))
  end

  test "AUTH-12: multiple comma-separated challenges at the top level, in wire order" do
    challenges = Challenges.parse("#{ChallengeFixtures::BASIC}, #{ChallengeFixtures::DIGEST_MD5}")

    assert_equal(%w[basic digest], challenges.map(&:scheme))
    assert_equal({ "realm" => "example" }, challenges[0].params)
    assert_equal("dcd98b7102dd2f0e8b11d0f600bfb0c093", challenges[1].params["nonce"])
    assert_equal("auth,auth-int", challenges[1].params["qop"])
  end

  test "AUTH-12: scheme and parameter names are lower-cased, values kept verbatim" do
    assert_equal([["basic", { "realm" => "MiXeD" }]], shapes('BASIC REALM="MiXeD"'))
    assert_equal([["digest", { "algorithm" => "SHA-256" }]], shapes("Digest Algorithm=SHA-256"))
  end

  test "AUTH-12: a quoted-string may contain commas and equals signs" do
    assert_equal("a, b = c", Challenges.parse('Digest realm="a, b = c"').first.params["realm"])
    assert_equal(1, Challenges.parse('Digest realm="a, b = c", nonce="x,y"').size)
  end

  test "AUTH-12: backslash escapes are unescaped and the quotes stripped" do
    assert_equal('a"b', Challenges.parse('Digest realm="a\\"b"').first.params["realm"])
    assert_equal("a\\b", Challenges.parse('Digest realm="a\\\\b"').first.params["realm"])
  end

  test "AUTH-12: a bare scheme with no params is a challenge with an empty parameter map" do
    assert_equal([["ntlm", {}]], shapes("NTLM"))
    assert_equal([["negotiate", {}], ["ntlm", {}]], shapes("Negotiate, NTLM"))
  end

  test "AUTH-12: a token68 value is recorded whole under the synthetic key, padding included" do
    challenge = Challenges.parse(ChallengeFixtures::BARE_TOKEN68).first

    assert_equal("dGhlIHNlY3JldCB0b2tlbg==", challenge.params["token68"])
    assert_equal("dGhlIHNlY3JldCB0b2tlbg==", challenge.token68)
    assert_equal([["bearer", { "token68" => "abc" }], ["basic", { "realm" => "r" }]],
                 shapes("Bearer abc, Basic realm=r"),)
  end

  test "AUTH-12: `realm=` is not read as a token68, so a Digest challenge keeps its realm" do
    assert_equal([["digest", { "realm" => "r" }]], shapes('Digest realm="r"'))
    assert_equal([["digest", { "realm" => "r", "nonce" => "n" }]],
                 shapes("Digest realm=r, nonce=n"),)
  end

  test "AUTH-12: a second challenge after a parameterised first is not swallowed" do
    challenges = Challenges.parse('Digest realm="r", nonce="n", Basic realm="r"')

    assert_equal(%w[digest basic], challenges.map(&:scheme))
    assert_equal({ "realm" => "r", "nonce" => "n" }, challenges.first.params)
    assert_equal({ "realm" => "r" }, challenges.last.params)
  end

  test "AUTH-13: empty list elements are skipped and the parameter continues the challenge" do
    assert_equal([["digest", { "realm" => "r", "nonce" => "n" }], ["basic", { "realm" => "ok" }]],
                 shapes("#{ChallengeFixtures::MALFORMED_STRAY_COMMA}, Basic realm=\"ok\""),)
  end

  test "AUTH-13: a malformed value recovers to the next top-level comma, keeping earlier params" do
    challenges = Challenges.parse("#{ChallengeFixtures::MALFORMED_VALUE}, Basic realm=\"ok\"")

    assert_equal(%w[digest basic], challenges.map(&:scheme))
    assert_equal({ "nonce" => "n" }, challenges.first.params)
  end

  test "AUTH-13: recovery walks a quoted string, so a comma inside one is not the boundary" do
    challenges = Challenges.parse('Digest realm=@@ nonce="a,b", Basic realm=x')

    assert_equal(%w[digest basic], challenges.map(&:scheme))
    assert_equal({ "realm" => "x" }, challenges.last.params)
  end

  test "AUTH-13: a parameter before any scheme, and a bare token after one, are skipped" do
    assert_equal([["basic", { "realm" => "r" }]], shapes("realm=x, Basic realm=r"))
    assert_equal([["bearer", {}], ["basic", { "realm" => "r" }]],
                 shapes("Bearer abc realm=x, Basic realm=r"),)
  end

  test "AUTH-13: an unterminated quoted-string terminates at end-of-input" do
    challenge = Challenges.parse(ChallengeFixtures::MALFORMED_UNTERMINATED_QUOTE).first

    assert_equal("unterminated", challenge.params["realm"])
    assert_equal({ "realm" => "r", "nonce" => "n" },
                 Challenges.parse('Digest realm="r", nonce="n').first.params,)
  end

  # The last input is a UTF-8-tagged value with an invalid byte, on which StringScanner#scan
  # and String#downcase both raise ArgumentError: the parser scans it as bytes instead.
  test "AUTH-13: the parser never raises on adversarial input, invalid UTF-8 included" do
    every_ascii = (0x20..0x7E).map(&:chr).join
    invalid_utf8 = "Digest realm=\"caf\xE9\"".b.force_encoding(Encoding::UTF_8)
    inputs = ["\\" * 5000, ("a=" * 5000), ('"' * 5000), every_ascii, "=", "\"", ",=,",
              "Basic realm=\"\\", "\x00\xFF".b, "Digest realm=\"\xC3\xA9\"".b, invalid_utf8,]

    inputs.each do |input|
      assert_kind_of(Array, Challenges.parse(input), input.inspect)
    end
  end

  test "the regexp-timeout house rule is discharged by measurement: 100 000 bytes in under 1 s" do
    inputs = ["a" * 100_000, ("a=b," * 25_000), ('"' * 100_000), ("Basic " * 16_000)]

    inputs.each do |input|
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Challenges.parse(input)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      assert_operator(elapsed, :<, 1.0)
    end
  end

  test "the list and every challenge are frozen" do
    challenges = Challenges.parse("Basic realm=r")

    assert_predicate(challenges, :frozen?)
    assert_predicate(challenges.first.params, :frozen?)
  end
end
