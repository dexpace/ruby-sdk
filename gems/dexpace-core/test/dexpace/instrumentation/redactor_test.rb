# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/allocation_delta"
require_relative "../../../lib/dexpace/instrumentation/redactor"

# Exercises: OBS-11, OBS-12, OBS-13, OBS-14, OBS-15, OBS-16, OBS-17, OBS-18, XCUT-11, XCUT-19,
# XCUT-20
#
# The port's security surface. Every negative here is the chapter's own conformance wording --
# "neither the username nor password substring appears" -- because a redaction applied to the
# wrong component passes any assertion written only on the component it did redact. Nothing is
# asserted with assert_nothing_raised (testing/26b866e1): totality is asserted on the substituted
# value.
#
# Split into nested classes under Metrics/ClassLength: the URL entry point, the header entry
# point, that entry point's surgery route, the shape.
class DexpaceInstrumentationRedactorTest < DexpaceTestCase
  Redactor = Dexpace::Instrumentation::Redactor
  Policy = Dexpace::Instrumentation::RedactionPolicy

  test "OBS-11, XCUT-19(a): userinfo is redacted to ***:***@ unconditionally, with no allow-list" do
    redacted = Redactor::DEFAULT.url("https://alice:s3cret@example.com/path?api-version=1")

    assert_equal("https://***:***@example.com/path?api-version=1", redacted)
    refute_includes(redacted, "alice")
    refute_includes(redacted, "s3cret")
    # A user with no password still gets the full two-part placeholder: that there was no
    # password is itself a fact about the credential.
    assert_equal("https://***:***@example.com/", Redactor::DEFAULT.url("https://alice@example.com/"))
    # Percent-encoded userinfo is redacted too, and nothing of it survives.
    encoded = Redactor::DEFAULT.url("https://al%40ice:p%3Ass@example.com/")

    assert_equal("https://***:***@example.com/", encoded)
  end

  test "OBS-12: query values are *** unless the decoded, folded name is allow-listed" do
    url = "https://example.com/p?api-version=2026-01-01&token=secret&API-Version=2&api%2Dversion=3"

    assert_equal("https://example.com/p?api-version=2026-01-01&token=***&API-Version=2&api%2Dversion=3",
                 Redactor::DEFAULT.url(url),)
  end

  test "OBS-12: multi-value keys are atomic, names and = are preserved, a bare token is kept" do
    assert_equal("https://h/p?token=***&token=***&token=***&flag&empty=***",
                 Redactor::DEFAULT.url("https://h/p?token=1&token=2&token=3&flag&empty="),)
  end

  test "OBS-12: an empty allow-list redacts every value, including api-version" do
    redactor = Redactor.build(policy: Policy.build(query_allow_list: []))

    assert_equal("https://h/p?api-version=***&token=***", redactor.url("https://h/p?api-version=1&token=x"))
  end

  # Verified fact 7: the parser accepts %FF, decoding it yields invalid UTF-8, and #downcase on
  # that raises ArgumentError, which is NOT a URI::Error. The name cannot match, so its value is
  # redacted -- the safe direction -- and nothing escapes.
  test "OBS-12, OBS-15, P5-26: an invalid-UTF-8 parameter name redacts and does not raise" do
    assert_equal("https://h/p?%FF=***&api-version=1",
                 Redactor::DEFAULT.url("https://h/p?%FF=secret&api-version=1"),)
  end

  test "OBS-13: key=value tokens in a fragment follow the query rule; a plain fragment is kept" do
    assert_equal("https://h/p#access_token=***", Redactor::DEFAULT.url("https://h/p#access_token=SECRET"))
    assert_equal("https://h/p#api-version=1&t=***", Redactor::DEFAULT.url("https://h/p#api-version=1&t=2"))
    assert_equal("https://h/p#section", Redactor::DEFAULT.url("https://h/p#section"))
    assert_equal("https://h/p#a/b?c", Redactor::DEFAULT.url("https://h/p#a/b?c"))
  end

  # P5-91: reassembled from RFC3986_PARSER.split's raw components, never URI#to_s, which drops
  # a default port -- so `:80` and `:443` survive, as OBS-14's "MUST NOT alter ... port" says.
  test "OBS-14: scheme, host, port and path are untouched and a trailing ? survives" do
    assert_equal("https://Example.COM:8443/A/b%20c?", Redactor::DEFAULT.url("https://Example.COM:8443/A/b%20c?"))
    assert_equal("http://h:80/", Redactor::DEFAULT.url("http://h:80/"))
    assert_equal("https://h:443/p?t=***", Redactor::DEFAULT.url("https://h:443/p?t=1"))
    assert_equal("https://[::1]:8080/p", Redactor::DEFAULT.url("https://[::1]:8080/p"))
    assert_equal("file:///etc/hosts", Redactor::DEFAULT.url("file:///etc/hosts"))
    assert_equal("//h/p?a=***", Redactor::DEFAULT.url("//h/p?a=1"))
    assert_equal("/relative?a=***#b", Redactor::DEFAULT.url("/relative?a=1#b"))
    assert_equal("", Redactor::DEFAULT.url(""))
    assert_equal("https://h/p", Redactor::DEFAULT.url("https://h/p"))
    assert_equal("http://h?", Redactor::DEFAULT.url("http://h?"))
    assert_equal("http://h#", Redactor::DEFAULT.url("http://h#"))
  end

  # The chapter's own case: a ? that appears only inside the fragment is not a query delimiter,
  # so no ? precedes the #. The fragment carries an =, so OBS-13 redacts it to a?b=***.
  test "OBS-14: a ? inside the fragment inserts no separator before the #" do
    redacted = Redactor::DEFAULT.url("http://h/p#a?b=c")
    before, after = redacted.split("#", 2)

    assert_equal("http://h/p", before)
    refute_includes(before, "?")
    assert_equal("a?b=***", after)
  end

  test "OBS-14: a trailing & (empty final pair) is dropped in a query and in a fragment" do
    assert_equal("https://h/p?a=***", Redactor::DEFAULT.url("https://h/p?a=1&"))
    assert_equal("https://h/p?a=***&&b=***", Redactor::DEFAULT.url("https://h/p?a=1&&b=2"))
    assert_equal("https://h/p#a=***", Redactor::DEFAULT.url("https://h/p#a=1&"))
  end

  test "OBS-15, XCUT-20: every parse failure yields the sentinel and nothing raises" do
    ["not a url at all", "https://h/a b", "http://[::1", "http://h/%zz", nil, 0.chr,
     "https://h/x?a=%FF#%zz=1",].each do |input|
      assert_equal(Redactor::MALFORMED_URL, Redactor::DEFAULT.url(input), input.inspect)
    end
    assert_equal("[malformed url]", Redactor::MALFORMED_URL)
    # RFC3986_PARSER.split -- the parse this redactor uses -- accepts a bad percent-encoding in a
    # query VALUE where #parse would reject it; the value is redacted, so nothing leaks either way.
    assert_equal("https://h/x?a=***", Redactor::DEFAULT.url("https://h/x?a=%zz"))
  end

  # P5-101: `split` accepts a bad percent-encoding in a query NAME too (`%zz`; in a FRAGMENT it
  # rejects one, hence the sentinel case above), and the decoder raises on it. The name is
  # unmatchable and costs one value, not the whole URL -- the direction `%FF` already takes --
  # so a parseable URL with one broken name still logs its host and path, and the
  # sentinel-fallback route of #header_value no longer has this trigger.
  test "OBS-12, OBS-15, P5-101: a bad percent-encoding in a parameter name is unmatchable" do
    assert_equal("https://h/p?%zz=***&api-version=2&b=***",
                 Redactor::DEFAULT.url("https://h/p?%zz=1&api-version=2&b=3"),)
    assert_equal("https://***:***@h/p?%zz=***", Redactor::DEFAULT.url("https://user:secret@h/p?%zz=1"))
    assert_equal("https://h/p?a%=***", Redactor::DEFAULT.url("https://h/p?a%=1"))
    # An allow-list that names the broken spelling literally still cannot match it: the name
    # never decodes, so the safe direction holds against a policy too.
    literal = Redactor.build(policy: Policy.build(query_allow_list: ["%zz"]))

    assert_equal("https://h/p?%zz=***", literal.url("https://h/p?%zz=1"))
  end

  # P5-27, P5-91: an opaque URI has userinfo, query and fragment all nil, and nothing absent is
  # ever written back, so the URI::InvalidURIError the setters would raise is unreachable.
  test "OBS-15, P5-27: an opaque URI round-trips untouched -- nothing absent is written back" do
    assert_equal("mailto:support@example.com", Redactor::DEFAULT.url("mailto:support@example.com"))
    assert_equal("urn:isbn:0451450523", Redactor::DEFAULT.url("urn:isbn:0451450523"))
    assert_equal("data:text/plain,hello", Redactor::DEFAULT.url("data:text/plain,hello"))
  end

  # P5-101: the pinned parser folds an opaque URI's `?query` INTO the opaque component (query
  # nil) while still splitting the fragment out, so the tail after the first `?` takes OBS-12's
  # rule and the address before it -- not a userinfo -- is written back untouched.
  test "OBS-12, OBS-15, P5-101: an opaque URI's query-shaped tail is redacted, its address kept" do
    assert_equal("mailto:support@example.com?subject=***",
                 Redactor::DEFAULT.url("mailto:support@example.com?subject=SECRET"),)
    assert_equal("mailto:a@b?x=***&api-version=1#frag",
                 Redactor::DEFAULT.url("mailto:a@b?x=1&api-version=1#frag"),)
    assert_equal("urn:isbn:1?q=***", Redactor::DEFAULT.url("urn:isbn:1?q=1"))
    assert_equal("data:text/plain,hello?x=***", Redactor::DEFAULT.url("data:text/plain,hello?x=1"))
  end

  # The rebuild rescue is the totality backstop, not the mechanism, so it is driven directly
  # rather than left with a comment claiming it is unreachable: a policy whose allow-list read
  # raises drives the rewrite into the rescue on an ordinary URL.
  test "OBS-15, P5-26: a rebuild failure yields the sentinel -- the rescue is StandardError" do
    exploding = ::Object.new
    def exploding.query_allow_list = raise("policy exploded")

    assert_equal(Redactor::MALFORMED_URL, Redactor.build(policy: exploding).url("https://h/p?a=1"))
  end

  test "OBS-11, OBS-12, OBS-13: a URI::Generic input is accepted and redacted like a String" do
    parsed = ::URI::RFC3986_PARSER.parse("https://u:p@h/x?k=v#k=v")

    assert_equal("https://***:***@h/x?k=***#k=***", Redactor::DEFAULT.url(parsed))
  end

  # OBS-16 and OBS-17: the header entry point.
  class HeaderValueTest < DexpaceTestCase
    Redactor = Dexpace::Instrumentation::Redactor
    Policy = Dexpace::Instrumentation::RedactionPolicy

    test "OBS-16: a parseable absolute value is redacted exactly like a request URL" do
      assert_equal("https://***:***@h/cb?code=***&api-version=1",
                   Redactor::DEFAULT.header_value("Location", "https://u:p@h/cb?code=S&api-version=1"),)
    end

    test "OBS-16: a relative value keeps its path and drops query and fragment behind ?***" do
      assert_equal("/cb?***", Redactor::DEFAULT.header_value("location", "/cb?code=SECRET"))
      assert_equal("/cb?***", Redactor::DEFAULT.header_value("location", "/cb#access_token=T"))
      assert_equal("/cb?***", Redactor::DEFAULT.header_value("location", "/cb?a=1#b=2"))
      # A present-but-empty query is a query: the presence test is !nil?, not truthiness.
      assert_equal("/cb?***", Redactor::DEFAULT.header_value("location", "/cb?"))
      # A fragment-only value has an empty path, so the marker is all that is left.
      assert_equal("?***", Redactor::DEFAULT.header_value("location", "#frag"))
    end

    test "OBS-16: a relative value with neither query nor fragment is returned verbatim" do
      assert_equal("/static/path", Redactor::DEFAULT.header_value("location", "/static/path"))
      assert_equal("relative/no/slash",
                   Redactor::DEFAULT.header_value("location", "relative/no/slash"),)
      assert_equal("", Redactor::DEFAULT.header_value("location", ""))
      # A network-path reference is relative too, and its authority is written back byte for
      # byte when it carries no userinfo: host, port and an IPv6 literal included.
      assert_equal("//h/x", Redactor::DEFAULT.header_value("location", "//h/x"))
      assert_equal("//[::1]:8443/x", Redactor::DEFAULT.header_value("location", "//[::1]:8443/x"))
      assert_equal("//h:8443/x?***", Redactor::DEFAULT.header_value("location", "//h:8443/x#f"))
    end

    # P5-100: OBS-11 is unconditional and OBS-16's "returned verbatim" is not an exception to
    # it. A network-path reference splits with an authority and no scheme, so it took the
    # relative route -- and the round-0 review found that route handed `//user:secret@h/x`
    # back verbatim. The authority is now rebuilt with the placeholder on that route too.
    test "OBS-11, OBS-16, P5-100: the relative route redacts a network-path reference's userinfo" do
      assert_equal("//***:***@h/x", Redactor::DEFAULT.header_value("Location", "//user:secret@h/x"))
      assert_equal("//***:***@h/x?***",
                   Redactor::DEFAULT.header_value("Location", "//user:secret@h/x?code=S"),)
      assert_equal("//***:***@[::1]:80/x?***",
                   Redactor::DEFAULT.header_value("Location", "//user:pw@[::1]:80/x?q=1"),)
      assert_equal("//***:***@h", Redactor::DEFAULT.header_value("Location", "//user@h"))
      %w[//user:secret@h/x //user:secret@h/x?code=S].each do |hostile|
        redacted = Redactor::DEFAULT.header_value("Location", hostile)

        refute_includes(redacted, "user")
        refute_includes(redacted, "secret")
      end
    end

    # P5-25: this entry point never yields OBS-15's sentinel -- a Location a reader cannot see
    # the path of is a useless log line. A policy whose allow-list read raises would send the
    # absolute route to the sentinel; it falls through to the surgery form instead.
    test "OBS-16, P5-25: header_value never returns the malformed sentinel" do
      exploding = ::Object.new
      def exploding.query_allow_list = raise("policy exploded")
      def exploding.url_header_names = ::Set["location"]
      redactor = Redactor.build(policy: exploding)

      assert_equal("https://h/p?***", redactor.header_value("location", "https://h/p?a=1"))
      assert_equal("https://h/p", redactor.header_value("location", "https://h/p"))
      # P5-100: the fallback is the surgery route, so a userinfo does not survive it either.
      assert_equal("https://***:***@h/p?***",
                   redactor.header_value("location", "https://user:secret@h/p?a=1"),)
      assert_equal("https://***:***@h/p", redactor.header_value("location", "https://user:secret@h/p"))
    end

    test "OBS-17: only the policy's URL-valued headers go through the URL redactor" do
      assert_equal("/p?***", Redactor::DEFAULT.header_value("Content-Location", "/p?t=1"))
      assert_equal("/p?t=1", Redactor::DEFAULT.header_value("Link", "/p?t=1"))
      assert_equal("application/json; charset=utf-8",
                   Redactor::DEFAULT.header_value("content-type",
                                                  "application/json; charset=utf-8",),)
      widened = Redactor.build(policy: Policy::DEFAULT.with(url_header_names: %w[location link]))

      assert_equal("/p?***", widened.header_value("Link", "/p?t=1"))
    end

    # The totality backstop on this entry point: a policy whose URL-header lookup raises drives
    # the whole method into its rescue, and what comes out is the marker, never a raise and
    # never the sentinel (P5-25, XCUT-20).
    test "OBS-16, XCUT-20: a failure anywhere in header_value yields the relative marker" do
      exploding = ::Object.new
      def exploding.url_header_names = raise("policy exploded")

      hostile = Redactor.build(policy: exploding)

      assert_equal(Redactor::RELATIVE_MARKER, hostile.header_value("x", "v"))
    end

    # api-design/6ea28c9c's "never nil for absent" is overruled here by requirement: OBS-16's
    # output is a header value, and nil is not one. Event#field never routes a nil here.
    test "OBS-16: header_value returns a String always: nil becomes empty, others stringify" do
      assert_equal("", Redactor::DEFAULT.header_value("location", nil))
      assert_equal("42", Redactor::DEFAULT.header_value("content-length", 42))
      assert_equal("", Redactor::DEFAULT.header_value(nil, nil))
    end
  end

  # OBS-16's third route (P5-28) -- a value the parser rejects, redacted by string surgery on
  # the raw value -- and OBS-11 on it (P5-100, P5-105, P5-107).
  class SurgeryRouteTest < DexpaceTestCase
    Redactor = Dexpace::Instrumentation::Redactor

    # P5-100, the surgery half: a value the parser rejects has no userinfo component to read,
    # so the authority's userinfo is substituted on the raw value before the cut -- and that
    # covers the sentinel-fallback route as well, which runs the same surgery.
    test "OBS-11, OBS-16, P5-100: the surgery route redacts an authority's userinfo, then cuts" do
      assert_equal("http://***:***@h/p x",
                   Redactor::DEFAULT.header_value("Location", "http://user:secret@h/p x"),)
      assert_equal("http://***:***@h/p x?***",
                   Redactor::DEFAULT.header_value("Location", "http://user:secret@h/p x?code=S"),)
      assert_equal("//***:***@h/p x", Redactor::DEFAULT.header_value("Location", "//user:pw@h/p x"))
      assert_equal("HTTP://***:***@h/p",
                   Redactor::DEFAULT.header_value("Location", "HTTP://us er:pw@h/p"),)
      # Up to the LAST @ before the first /, ? or #: a stray @ inside the userinfo hides nothing.
      assert_equal("http://***:***@h/p x?***",
                   Redactor::DEFAULT.header_value("Location", "http://a@b@h/p x?q"),)
      # An @ after the first / is in the path, not the authority; there is no userinfo to redact.
      assert_equal("http://us/er:pw@h/p x",
                   Redactor::DEFAULT.header_value("Location", "http://us/er:pw@h/p x"),)
    end

    # P5-105 (review round 1's R1-3): HTTP-19's grammar admits a leading OWS in an inbound
    # header value, the parser rejects a value that starts with one, and the surgery pattern was
    # anchored at the scheme -- so a Location built with a leading space carried its userinfo
    # through. The leading bytes are written back as they came and the userinfo behind them is
    # substituted.
    test "OBS-11, OBS-16, P5-105: leading whitespace or a control byte before the scheme" do
      { " http://user:secret@h/p" => " http://***:***@h/p",
        "\thttp://user:secret@h/p" => "\thttp://***:***@h/p",
        " //user:secret@h/x" => " //***:***@h/x",
        "  http://user:secret@h/p?code=S" => "  http://***:***@h/p?***",
        "\vhttp://user:secret@h/p" => "\vhttp://***:***@h/p",
        "\u0000http://user:secret@h/p" => "\u0000http://***:***@h/p",
        " http://user:secret@h/p\xFF".b => " http://***:***@h/p\xFF".b, }.each do |value, expected|
        assert_equal(expected, Redactor::DEFAULT.header_value("Location", value), value.inspect)
      end
    end

    # P5-107 (review round 2's R2-1): P5-105 tolerated whitespace and controls and nothing
    # else, so ANY other prefix before a real `scheme://user:secret@host` -- RFC 3986 Appendix
    # C's own `<…>`, quotes, parentheses, a word, an encoded space, `+`, `@`, a backslash, an
    # NBSP, an obs-text byte -- carried the userinfo through, and so did the second authority
    # of a doubled URL. The surgery route now substitutes EVERY `//`-authority's userinfo
    # wherever it sits: a value the parser rejected has no grammar left to honour.
    test "OBS-11, OBS-16, P5-107: every //-authority in a rejected value loses its userinfo" do
      cases = {
        "<http://user:secret@h/p>" => "<http://***:***@h/p>",
        "\"http://user:secret@h/p?code=S\"" => "\"http://***:***@h/p?***",
        "'http://user:secret@h/p'" => "'http://***:***@h/p'",
        "(http://user:secret@h/p)" => "(http://***:***@h/p)",
        "x http://user:secret@h/p" => "x http://***:***@h/p",
        "%20http://user:secret@h/p" => "%20http://***:***@h/p",
        "+http://user:secret@h/p" => "+http://***:***@h/p",
        "@http://user:secret@h/p" => "@http://***:***@h/p",
        "\\http://user:secret@h/p" => "\\http://***:***@h/p",
        "\u00a0http://user:secret@h/p" => "\u00a0http://***:***@h/p",
        "\u2028http://user:secret@h/p" => "\u2028http://***:***@h/p",
        "\u00e9://user:secret@h/p" => "\u00e9://***:***@h/p",
        "\xC2\xA0http://user:secret@h/p".b => "\xC2\xA0http://***:***@h/p".b,
        "\xFFhttp://user:secret@h/p".b => "\xFFhttp://***:***@h/p".b,
        "\xA0http://user:secret@h/p?code=S".b => "\xA0http://***:***@h/p?***".b,
        # A doubled proxy URL: the second authority sat behind the first, where an anchored
        # `sub` never reached (the port `3128http` is what rejects it).
        "http://user:secret@proxy.corp:3128http://user:secret@proxy.corp:3128" =>
          "http://***:***@proxy.corp:3128http://***:***@proxy.corp:3128",
      }
      cases.each do |value, expected|
        redacted = Redactor::DEFAULT.header_value("Location", value)

        assert_equal(expected, redacted, value.inspect)
        refute_includes(redacted.b, "secret", value.inspect)
      end
      # What is still not an authority under RFC 3986 and is written back as given (P5-100):
      # no `//` before the `@` (a path or an opaque part, and only a proxy URL's own grammar
      # can call it a credential -- the resolver's belt, P5-103), the backslash spellings (a
      # backslash is not a URI character), a `/ /` that is not a `//`, and what the parser
      # ACCEPTS without an authority -- an empty authority with the credential in the path, a
      # path-absolute reference, a network-path reference that splits as a path -- which never
      # reaches the surgery route at all.
      ["user:secret@h/p", "http:\\\\user:secret@h\\p", "\\\\user:secret@h/p",
       "http:/ /user:secret@h/p", "http:///user:secret@h/p", "/http://user:secret@h/p",
       "//@user:secret@h/x",].each do |value|
        assert_equal(value, Redactor::DEFAULT.header_value("Location", value))
      end
      # A parseable URL whose PATH spells a second authority is a valid URI, and OBS-14 forbids
      # altering the path: the authority is redacted and the path is the path.
      assert_equal("http://***:***@h/phttp://user:secret@h/p",
                   Redactor::DEFAULT.header_value("Location", "http://user:secret@h/phttp://user:secret@h/p"),)
    end

    # P5-28: an unparseable value has no parsed object to read #path from, so the path is the
    # raw value up to the first ? or #, whichever comes first.
    test "OBS-16, P5-28: an unparseable value takes the string-surgery route" do
      assert_equal("bad path?***", Redactor::DEFAULT.header_value("location", "bad path?secret=1"))
      assert_equal("bad path?***", Redactor::DEFAULT.header_value("location", "bad path#frag?x"))
      assert_equal("bad path", Redactor::DEFAULT.header_value("location", "bad path"))
      assert_equal("https://h/a b?***",
                   Redactor::DEFAULT.header_value("location", "https://h/a b?c=1"),)
    end
  end

  # OBS-18's gate and the shape XCUT-11 audits.
  class ShapeTest < DexpaceTestCase
    include AllocationDelta

    Redactor = Dexpace::Instrumentation::Redactor
    Policy = Dexpace::Instrumentation::RedactionPolicy

    test "OBS-18: header_name? answers against the folded allow-list" do
      assert(Redactor::DEFAULT.header_name?("content-type"))
      assert(Redactor::DEFAULT.header_name?("Content-Type"))
      assert(Redactor::DEFAULT.header_name?(:Accept))
      refute(Redactor::DEFAULT.header_name?("authorization"))
      refute(Redactor::DEFAULT.header_name?("Authorization"))
      refute(Redactor::DEFAULT.header_name?("cookie"))
      refute(Redactor::DEFAULT.header_name?(nil))
      refute(Redactor::DEFAULT.header_name?(""))
    end

    test "the five markers are the spec's fixed spellings" do
      assert_equal("[malformed url]", Redactor::MALFORMED_URL)
      assert_equal("***", Redactor::REDACTED_VALUE)
      assert_equal("***:***", Redactor::REDACTED_USERINFO)
      assert_equal("REDACTED", Redactor::REDACTED_HEADER)
      assert_equal("?***", Redactor::RELATIVE_MARKER)
      # The surgery route's pattern is a mechanism, not surface, and carries its own timeout
      # rather than the process-wide Regexp.timeout (P5-100).
      assert_raises(::NameError) { Redactor::SURGERY_USERINFO }
      pattern = Redactor.const_get(:SURGERY_USERINFO)

      assert_in_delta(1.0, pattern.timeout)
    end

    # XCUT-11: frozen, holding a frozen policy, no per-call state -- every intermediate is a
    # method local -- so the shared DEFAULT is safe from any thread by construction.
    test "XCUT-11: a Redactor is frozen, holds a frozen policy and exposes it for derivation" do
      assert_predicate(Redactor::DEFAULT, :frozen?)
      assert_same(Policy::DEFAULT, Redactor::DEFAULT.policy)
      assert_predicate(Redactor.build.policy, :frozen?)
      refute_respond_to(Redactor, :new)
      assert_empty(Redactor::DEFAULT.instance_variables - [:@policy])
      results = Array.new(8) do
        ::Thread.new do
          Redactor::DEFAULT.url("https://u:p@h/?t=1")
        end
      end.map(&:value)

      assert_equal(["https://***:***@h/?t=***"] * 8, results)
    end

    test "a redactor takes a policy and refuses something that is not one" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Redactor.build(policy: nil) }
      assert_match(/policy/, error.message)
    end
  end
end
