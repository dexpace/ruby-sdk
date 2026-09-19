# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"
require_relative "../../test_helper"

# Exercises: REDIR-8, REDIR-12, REDIR-13, REDIR-14, REDIR-16, REDIR-18, REDIR-19, REDIR-20 (the
# Ruby facts they rest on) -- the phase-6b design's four verified facts plus the ones the build
# found, re-run as a standing test on every CI row rather than once in a scratch script (5a's,
# 5b's, 5c's, 6a's and 6c's precedent). Run on 3.2.11, 3.3.12, 3.4.10 and 4.0.6 on 2026-09-19:
# every fact holds identically on every row, and the one thing that differs across the matrix
# is URI::InvalidURIError's MESSAGE -- a uri-GEM difference (0.13.3, 3.3.12's default, prints
# "bad URI(is not URI?)"; 1.0.4 and 1.1.1 print "bad URI (is not URI?)"), which is why no
# assertion anywhere in this phase matches it (url-and-query-encoding/08c54234). No lib/ mirror:
# it asserts the interpreter, not a file.
class DexpaceRedirectMatrixFactsTest < DexpaceTestCase
  PARSER = ::URI::RFC3986_PARSER

  test "REDIR-12 fact 1: userinfo = \"\" clears user AND password; userinfo = nil is a no-op" do
    stripped = PARSER.parse("https://user:pass@ex.com/p?q=1")
    stripped.userinfo = ""

    assert_equal("https://ex.com/p?q=1", stripped.to_s)
    assert_nil(stripped.user)
    assert_nil(stripped.password)

    untouched = PARSER.parse("https://user:pass@ex.com/p?q=1")
    untouched.userinfo = nil

    assert_equal("https://user:pass@ex.com/p?q=1", untouched.to_s) # the credential survives
  end

  test "REDIR-12 fact 1: a frozen URI refuses the strip, so the freeze comes AFTER it" do
    frozen = PARSER.parse("https://user:pass@ex.com/p").freeze

    assert_raises(FrozenError) { frozen.userinfo = "" }
  end

  test "REDIR-14 fact 2: join resolves a relative reference against the base and takes an " \
       "absolute one as-is" do
    assert_equal("https://h/v2/x", PARSER.join("https://h/v1/x", "/v2/x").to_s)
    assert_equal("https://other/y", PARSER.join("https://h/v1/x?a=1", "https://other/y").to_s)
    assert_equal("https://h/v1/x?q=2", PARSER.join("https://h/v1/x?q=1", "?q=2").to_s)
    assert_equal("https://other/p", PARSER.join("https://h/v1/x", "//other/p").to_s)
  end

  test "REDIR-13 fact 2: join preserves %2F, %2B, a bracketed IPv6 host and a non-default port" do
    assert_equal("https://ex.com/d%2Fe?q=%2Bz",
                 PARSER.join("https://ex.com/a%2Fb/c?x=%26y#f", "/d%2Fe?q=%2Bz").to_s,)
    assert_equal("https://[2001:db8::1]:8443/q",
                 PARSER.join("https://[2001:db8::1]:8443/p", "/q").to_s,)
    assert_equal("https://h:8443/v1/y", PARSER.join("https://h:8443/v1/x", "y").to_s)
  end

  test "REDIR-13 residue (P5-91): URI#to_s drops an EXPLICIT scheme-default port" do
    assert_equal("https://ex.com/x", PARSER.parse("https://ex.com:443/x").to_s)
    assert_equal("http://ex.com:8080/x", PARSER.parse("http://ex.com:8080/x").to_s)
    assert_equal(443, PARSER.parse("https://ex.com:443/x").port) # the OBJECT still knows
  end

  test "REDIR-18 fact 2: a malformed reference raises URI::InvalidURIError -- asserted by class" do
    ["ht!tp://user:pass@bad", "https://h/p q", "https://h/<p>", "https://h/pé",
     "https://h:notaport/", "/p\tq",].each do |reference|
      assert_raises(::URI::InvalidURIError, reference) do
        PARSER.join("https://a.example/base/x", reference)
      end
    end
  end

  test "REDIR-18: the plan's fixture https://user:pass@ht!tp://bad is a VALID URI" do
    # '!' is a sub-delim in reg-name, so this resolves to a host named "ht!tp" and would be
    # FOLLOWED by a test that meant it to fail parsing; the suite uses "ht!tp://user:pass@bad".
    resolved = PARSER.join("https://a.example/base/x", "https://user:pass@ht!tp://bad")

    assert_equal("ht!tp", resolved.host)
  end

  test "REDIR-18 fact 2: join raises on neither an unsupported scheme nor a host-less target" do
    mailto = PARSER.join("https://h/x", "mailto:a@b")

    assert_instance_of(::URI::MailTo, mailto)
    assert_nil(mailto.host)
    assert_raises(::URI::InvalidURIError) { mailto.userinfo = "" } # "cannot set user with opaque"
    assert_instance_of(::URI::FTP, PARSER.join("https://h/x", "ftp://o/z"))
    assert_nil(PARSER.join("https://h/x", "http:foo").host)
    assert_equal("", PARSER.join("https://h/x", "http:///p").host)
    assert_equal("", PARSER.join("https://h/x", "https://").host)
  end

  test "REDIR-19 fact: join(base, \"\") answers the base; join(base, nil) raises ArgumentError" do
    assert_equal("https://h/v1/x", PARSER.join("https://h/v1/x", "").to_s)
    assert_raises(ArgumentError) { PARSER.join("https://h/v1/x", nil) }
  end

  test "REDIR-8 fact 3: URI folds neither the host's case nor the scheme's through #host; " \
       "#port supplies the scheme default" do
    assert_equal("EX.com", PARSER.parse("https://EX.com/").host)
    assert_equal("EX.com", PARSER.join("https://h/x", "https://EX.com/y").host)
    assert_equal("https://Other/Y", PARSER.join("https://h/x", "HTTPS://Other/Y").to_s)
    assert_equal(443, PARSER.parse("https://ex.com/").port)
    assert_equal(80, PARSER.parse("http://ex.com/").port)
    assert_equal(443, PARSER.parse("https://ex.com:443/").port)
    assert_equal(8080, PARSER.parse("http://ex.com:8080/").port)
  end

  test "REDIR-20 fact 4: Set is insertion-ordered and a frozen one raises FrozenError" do
    forward = Set.new
    %w[a b c].each { |member| forward << member }
    backward = Set.new
    %w[c b a].each { |member| backward << member }

    assert_equal(%w[a b c], forward.to_a)
    assert_equal(%w[c b a], backward.to_a)
    assert_raises(FrozenError) { forward.dup.freeze << "d" }
  end

  test "REDIR-16: the design's Set-of-URI rationale is FALSE -- two parses of one string ARE " \
       "eql? and hash alike; the Set<String> choice stands on the external form alone" do
    first = PARSER.parse("https://h/x")
    second = PARSER.parse("https://h/x")

    assert_equal(first, second)
    assert(first.eql?(second))
    assert_equal(first.hash, second.hash)
    assert_includes(Set[first], second)
  end
end
