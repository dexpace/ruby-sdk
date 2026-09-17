# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# CFG-23: a non-proxy host glob compiled once at construction -- `*` any run, `?` one character,
# everything else escaped, full-string, case-insensitive, \A..\z and never \Z.
class DexpaceProxyHostPatternTest < DexpaceTestCase
  test "CFG-23: * matches any run and ? exactly one character, case-insensitively" do
    pattern = Dexpace::Proxy::HostPattern.of("*.example.com")

    assert(pattern.matches?("api.example.com"))
    assert(pattern.matches?("API.Example.COM"))
    assert(pattern.matches?("a.b.example.com"))
    refute(pattern.matches?("example.com")) # the apex is not matched by *.
    refute(pattern.matches?("api.example.org"))

    one = Dexpace::Proxy::HostPattern.of("test?.example.com")

    assert(one.matches?("test1.example.com"))
    refute(one.matches?("test12.example.com"))
    refute(one.matches?("test.example.com"))
  end

  test "CFG-23: every regexp metacharacter in the glob is literal" do
    dot = Dexpace::Proxy::HostPattern.of("a.b")

    assert(dot.matches?("a.b"))
    refute(dot.matches?("axb"))

    ["[a]", "a+b", "a|b", "(a)", "a{2}", "a^b", "a$b", "a\\d"].each do |glob|
      pattern = Dexpace::Proxy::HostPattern.of(glob)

      assert(pattern.matches?(glob), "glob #{glob}")
      assert(pattern.matches?(glob.upcase), "glob #{glob}")
      refute(pattern.matches?("aa"), "glob #{glob}")
    end
  end

  # \z and never \Z: a full-string match that accepts a trailing newline is not one, and a host
  # name arriving from configuration is exactly where a stray newline comes from. No /m either:
  # `*` stopping at \n is what keeps *.example.com from matching "evil.com\n.example.com".
  test "CFG-23: a newline in the host never matches -- \\z, not \\Z, and no /m" do
    exact = Dexpace::Proxy::HostPattern.of("evil.com")

    refute(exact.matches?("evil.com\n"))
    refute(exact.matches?("\nevil.com"))

    glob = Dexpace::Proxy::HostPattern.of("*.example.com")

    refute(glob.matches?("evil.com\n.example.com"))
    refute(glob.matches?("api.example.com\n"))
  end

  test "CFG-23: the host is matched as given -- never stripped, never nil-matched" do
    pattern = Dexpace::Proxy::HostPattern.of("host")

    refute(pattern.matches?(" host"))
    refute(pattern.matches?("host "))
    refute(pattern.matches?(nil))
    assert(pattern.matches?(:host))
  end

  test "CFG-23: the pattern is compiled once at construction with a per-pattern timeout" do
    pattern = Dexpace::Proxy::HostPattern.of("*.example.com")
    matcher = pattern.send(:matcher)

    assert_kind_of(Regexp, matcher)
    assert_same(matcher, pattern.send(:matcher))
    refute_nil(matcher.timeout)
    assert_equal('\A.*\.example\.com\z', matcher.source)
    assert_predicate(pattern, :frozen?)
    refute_respond_to(pattern, :matcher) # the compiled Regexp is not public surface
  end

  test "CFG-37 / SEAM-29: a nil or blank glob is refused, and .new is private" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy::HostPattern.of(nil) }

    assert_equal("glob is required", error.message)
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy::HostPattern.of("") }
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy::HostPattern.of("   ") }
    refute_respond_to(Dexpace::Proxy::HostPattern, :new)
  end

  test "HTTP-3: value equality is over the glob, and #with recompiles through .build" do
    assert_equal(Dexpace::Proxy::HostPattern.of("*.old"), Dexpace::Proxy::HostPattern.of("*.old"))
    assert_equal(Dexpace::Proxy::HostPattern.of("*.old").hash, Dexpace::Proxy::HostPattern.of("*.old").hash)
    refute_equal(Dexpace::Proxy::HostPattern.of("*.old"), Dexpace::Proxy::HostPattern.of("*.new"))

    # Model#with routes through .build, which re-enters initialize -- so the matcher is recompiled
    # from the new glob rather than carried over, on 3.2.11 as on 4.0.6 (Data#with alone would
    # skip the constructor on the floor and leave the old matcher in place).
    derived = Dexpace::Proxy::HostPattern.of("*.old").with(glob: "*.new")

    assert_equal("*.new", derived.glob)
    assert(derived.matches?("api.new"))
    refute(derived.matches?("api.old"))
    assert_raises(Dexpace::InvalidArgumentError) { derived.with(glob: "") }
  end

  # testing/f36a19cd: the parse-constructor round-trips, and a glob with no metacharacter matches
  # exactly itself in any case.
  test "property: .of(g).glob == g, and a metacharacter-free glob matches itself and its upcase" do
    alphabet = ("a".."z").to_a + ("0".."9").to_a + ["-", "."]
    sample(count: 128) do |rng|
      glob = Array.new(rng.rand(1..24)) { alphabet.sample(random: rng) }.join
      pattern = Dexpace::Proxy::HostPattern.of(glob)

      assert_equal(glob, pattern.glob)
      assert(pattern.matches?(glob), "glob #{glob}")
      assert(pattern.matches?(glob.upcase), "glob #{glob}")
      refute(pattern.matches?("#{glob}x"), "glob #{glob}")
    end
  end
end
