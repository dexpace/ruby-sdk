# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# Exercises: PAGE-18 (the grammar), PAGE-20 -- through the private_constant, reached the way 4c's
# cursor_test reaches Pipeline::Cursor.
#
# A character-level state machine, not a regexp: RFC 8288's link-value grammar is not regular
# (commas inside <> and inside quoted parameter values must not split link-values, and quoted-pair
# escapes must be honoured), so the per-pattern-timeout constraint is discharged by not writing the
# pattern -- the same route design §6.3 takes for WWW-Authenticate.
class DexpacePageLinkHeaderTest < DexpaceTestCase
  L = Dexpace::Page.const_get(:LinkHeader)

  test "PAGE-18: a comma inside an angle-bracketed URL does not split link-values" do
    assert_equal("https://x/p?a=1,2", L.next_target(['<https://x/p?a=1,2>; rel="next"']))
  end

  test "PAGE-18: a comma inside a quoted parameter value does not split link-values" do
    header = '<https://x/1>; title="a,b"; rel="prev", <https://x/2>; rel="next"'

    assert_equal("https://x/2", L.next_target([header]))
  end

  test "PAGE-18: a semicolon inside a quoted value does not split parameters" do
    assert_equal("https://x/2", L.next_target(['<https://x/2>; title="a;b"; rel="next"']))
  end

  test "PAGE-18: quoted-pair escapes are honoured" do
    header = '<https://x/1>; title="a\\"b, c"; rel="last", <https://x/2>; rel=next'

    assert_equal("https://x/2", L.next_target([header]))
    assert_equal("https://x/2", L.next_target(['<https://x/2>; rel="ne\\xt"'])) # \x is x
  end

  test "PAGE-18: rel may be unquoted, multi-token, and is matched case-insensitively" do
    assert_equal("https://x/2", L.next_target(["<https://x/2>; rel=NEXT"]))
    assert_equal("https://x/2", L.next_target(['<https://x/2>; rel="prev  next"']))
    assert_equal("https://x/2", L.next_target(["<https://x/2>; rel=\"last\tnext\""]))
    assert_equal("https://x/2", L.next_target(["<https://x/2>; REL=next"]))
  end

  test "PAGE-18: the token is next, not a word containing it" do
    assert_nil(L.next_target(['<https://x/2>; rel="nextish"']))
    assert_nil(L.next_target(['<https://x/2>; rel="prev-next"']))
    assert_nil(L.next_target(["<https://x/2>; relation=next"]))
  end

  test "PAGE-18: the FIRST link-value whose rel contains next wins" do
    assert_equal("https://x/1", L.next_target(["<https://x/1>; rel=next, <https://x/2>; rel=next"]))
    assert_equal("https://x/1", L.next_target(['<https://x/1>; rel="first next"; rel="prev"']))
  end

  test "PAGE-18: no rel=next segment and no header at all both mean end-of-stream" do
    assert_nil(L.next_target(["<https://x/1>; rel=prev, <https://x/9>; rel=last"]))
    assert_nil(L.next_target(["<https://x/1>"]))
    assert_nil(L.next_target(nil))
    assert_nil(L.next_target([]))
    assert_nil(L.next_target([""]))
  end

  test "PAGE-18: malformed input never raises -- it is end-of-stream or the best parse" do
    assert_nil(L.next_target(["https://x/2; rel=next"]))        # no angle brackets at all
    assert_nil(L.next_target(["<https://x/2; rel=next"]))       # never closed
    assert_nil(L.next_target(['<https://x/2>; rel="next']))     # quote never closed
    assert_nil(L.next_target(['<https://x/2>; rel="next\\']))   # escape at the very end
    assert_equal("https://x/2", L.next_target(["<https://x/2>;rel=next,"]))
    assert_equal("https://x/2", L.next_target([" , <https://x/2> ; rel = next ; "]))
    assert_equal("", L.next_target(["<>; rel=next"]))           # blank target: the strategy's P7-5
  end

  test "PAGE-20: multiple Link header instances are normalized by concatenation" do
    assert_equal("https://x/2",
                 L.next_target(["<https://x/9>; rel=last", "<https://x/2>; rel=next"]),)
    assert_equal("https://x/2",
                 L.next_target(["<https://x/2>; rel=next", "<https://x/9>; rel=last"]),)
  end

  test "no Regexp is compiled anywhere in the grammar" do
    source = File.read(File.expand_path("../../../lib/dexpace/page/link_header.rb", __dir__))

    refute_match(%r{Regexp\.new|=~|\.match\?|%r\{|/\\A}, source)
  end
end
