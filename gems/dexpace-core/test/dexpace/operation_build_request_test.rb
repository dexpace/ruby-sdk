# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# SEAM-27, and SEAM-26's "the body is carried, not encoded, by this seam".
#
# The composition is hand-built and is NOT RFC 3986 reference resolution. Verified on 3.2.11 and
# 4.0.6: URI::RFC3986_PARSER.join("https://host/c?sig=1", "/pets") is "https://host/pets" and
# #merge of the same is identical -- both discard the /c base segment and the sig query that
# SEAM-27's own conformance step requires to survive. Design §3.5's "base-URL composition uses
# URI.join/URI#merge" is superseded here (deviation P2-3,
# docs/knowledge/notes/url-and-query-encoding.md); reference resolution keeps its place at REDIR-13
# in phase 6, where the spelling is URI::RFC3986_PARSER.join because URI.join is cop-banned.
#
# Two classes because Metrics/ClassLength caps one at 100 lines: the composition rules here, and
# the four projections plus the property test in Projections.
class DexpaceOperationBuildRequestTest < DexpaceTestCase
  # The one operation shape every case builds, shared by both classes.
  module Builds
    def operation(template: "/pets", projections: {}, method: "GET")
      Dexpace::Operation.build(method: method, template: template, projections: projections)
    end

    def url_for(subject, base) = subject.build_request(base_url: base).url.to_s
  end
  include Builds

  test "the specification's own conformance example" do
    subject = operation(projections: { limit: [:query, "limit"] })

    request = subject.build_request(base_url: "https://host/c?sig=abc", inputs: { limit: 1 })

    assert_equal("https://host/c/pets?sig=abc&limit=1", request.url.to_s)
    assert_equal(Dexpace::Method::GET, request.method)
  end

  test "a trailing slash normalises to exactly one separator" do
    assert_equal("https://host/c/pets", url_for(operation, "https://host/c/"))
    assert_equal("https://host/c/pets", url_for(operation, "https://host/c"))
    assert_equal("https://host/pets", url_for(operation, "https://host"))
    assert_equal("https://host/c/pets", url_for(operation(template: "pets"), "https://host/c///"))
    assert_equal("https://host/c/pets", url_for(operation(template: "//pets"), "https://host/c/"))
  end

  test "an empty operation path leaves the base untouched" do
    subject = operation(template: "", projections: { limit: [:query, "limit"] })

    request = subject.build_request(base_url: "https://host/c", inputs: { limit: 1 })

    assert_equal("https://host/c?limit=1", request.url.to_s)
    assert_equal("https://host/c/", url_for(operation(template: ""), "https://host/c/"))
  end

  test "an existing base query is preserved with the operation query appended after it" do
    subject = operation(projections: { limit: [:query, "limit"] })

    request = subject.build_request(base_url: "https://host/c?sig=abc", inputs: { limit: 2 })

    assert_equal("https://host/c/pets?sig=abc&limit=2", request.url.to_s)
  end

  test "a dangling base separator is dropped" do
    subject = operation(projections: { limit: [:query, "limit"] })

    request = subject.build_request(base_url: "https://host/c?sig=abc&&", inputs: { limit: 2 })

    assert_equal("https://host/c/pets?sig=abc&limit=2", request.url.to_s)
    assert_equal("https://host/c/pets?sig=abc", url_for(operation, "https://host/c?sig=abc&"))
  end

  test "a base with no query and an operation with none yields no query at all" do
    assert_equal("https://host/pets", operation.build_request(base_url: "https://host").url.to_s)
  end

  test "a base carrying a fragment is rejected with a context-bearing error" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      operation.build_request(base_url: "https://host/c#section")
    end

    assert_match(/fragment/, error.message)
    assert_match(%r{https://host/c\#section}, error.message)
  end

  test "a malformed or relative base is rejected through phase 1's URL.parse!" do
    assert_raises(Dexpace::InvalidArgumentError) { operation.build_request(base_url: "/c") }
    assert_raises(Dexpace::InvalidArgumentError) { operation.build_request(base_url: "ht tp://x") }
    assert_raises(Dexpace::InvalidArgumentError) { operation.build_request(base_url: nil) }
  end

  test "already-encoded octets in the base survive the composition verbatim" do
    request = operation.build_request(base_url: "https://host/a%2Fb?x=%26")

    assert_equal("https://host/a%2Fb/pets?x=%26", request.url.to_s)
  end

  test "the composed URL re-parses to itself" do
    request = operation.build_request(base_url: "https://host/c")

    assert_equal(request.url.to_s, Dexpace::URL.parse!(request.url.to_s).to_s)
  end

  test "the composed URL is frozen and the base is untouched" do
    base = Dexpace::URL.parse!("https://host/c")

    request = operation.build_request(base_url: base)

    assert_predicate(request.url, :frozen?)
    assert_equal("https://host/c", base.to_s)
  end

  # The four projections, and the property test over path values.
  class Projections < DexpaceTestCase
    include Builds

    # The seam's whole security property, and it gets its own test rather than riding on a
    # composition assertion.
    test "a path value containing a slash is encoded, not split into segments" do
      subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

      request = subject.build_request(base_url: "https://host", inputs: { id: "a/b" })

      assert_equal("https://host/pets/a%2Fb", request.url.to_s)
      assert_equal(3, request.url.path.split("/").length, "one segment, not two")
    end

    test "a path value's reserved characters are all percent-encoded" do
      subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

      request = subject.build_request(base_url: "https://host", inputs: { id: "a b?c#d&e" })

      assert_equal("https://host/pets/a%20b%3Fc%23d%26e", request.url.to_s)
    end

    test "a missing placeholder value is loud and names the input key and the placeholder" do
      subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

      error = assert_raises(Dexpace::InvalidArgumentError) do
        subject.build_request(base_url: "https://host")
      end

      assert_match(/:id/, error.message)
      assert_match(/"id"/, error.message)
    end

    # A supplied nil is missing, not empty: SEAM-27 makes a placeholder with no value an error,
    # and an `inputs.key?` check alone would render "https://host/pets/" -- well-formed, wrong,
    # silent.
    test "a nil path input is missing, not an empty segment" do
      subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

      error = assert_raises(Dexpace::InvalidArgumentError) do
        subject.build_request(base_url: "https://host", inputs: { id: nil })
      end

      assert_match(/:id/, error.message)
    end

    test "false is a path value, not a missing one" do
      subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })

      request = subject.build_request(base_url: "https://host", inputs: { id: false })

      assert_equal("https://host/pets/false", request.url.to_s)
    end

    # Phase 1's Query::Builder#add coerces String, Symbol, Integer, Float, true and false through
    # #to_s and nil to "", and raises for a Hash or an Array. A generated client reaching for an
    # OpenAPI deepObject or a non-default style must fail here rather than render
    # "{:color=>\"red\"}" into the query -- a URL that is well-formed, wrong, and silent, which is
    # the same failure mode the nil-path-input test guards on the path side.
    test "a structured query value is refused, not rendered as an inspect string" do
      subject = operation(projections: { filter: [:query, "filter"] })

      assert_raises(Dexpace::InvalidArgumentError) do
        subject.build_request(base_url: "https://host", inputs: { filter: { color: "red" } })
      end
    end

    test "a repeated query projection emits one parameter per value" do
      subject = operation(projections: { tag: [:query, "tag"] })

      request = subject.build_request(base_url: "https://host", inputs: { tag: %w[a b] })

      assert_equal("https://host/pets?tag=a&tag=b", request.url.to_s)
    end

    # A nil query input is absent, exactly as an unsupplied one is -- the path side makes nil an
    # error because a placeholder cannot be left out, and a query parameter can. HTTP-28's
    # value-less parameter is reached with an empty string, which is a value.
    test "an absent or nil optional query input contributes nothing; an empty one is value-less" do
      subject = operation(projections: { tag: [:query, "tag"] })

      assert_equal("https://host/pets", subject.build_request(base_url: "https://host").url.to_s)
      assert_equal("https://host/pets",
                   subject.build_request(base_url: "https://host", inputs: { tag: nil }).url.to_s,)
      assert_equal("https://host/pets?tag=",
                   subject.build_request(base_url: "https://host", inputs: { tag: "" }).url.to_s,)
    end

    test "header projections go through the outbound header builder" do
      subject = operation(projections: { trace: [:header, "X-Trace"] })

      request = subject.build_request(base_url: "https://host", inputs: { trace: "abc" })

      assert_equal(["abc"], request.headers["X-Trace"])
      assert_equal(:outbound, request.headers.direction)
    end

    test "a header projection carrying a CRLF is rejected by phase 1's validation, here" do
      subject = operation(projections: { trace: [:header, "X-Trace"] })

      assert_raises(Dexpace::InvalidArgumentError) do
        subject.build_request(base_url: "https://host", inputs: { trace: "a\r\nInjected: yes" })
      end
    end

    test "the body is carried, not encoded" do
      subject = operation(method: "POST", projections: { payload: [:body, "body"] })
      payload = Object.new

      request = subject.build_request(base_url: "https://host", inputs: { payload: payload })

      assert_same(payload, request.body, "SEAM-26: encoding it is the codec's job at a later stage")
      assert_nil(subject.build_request(base_url: "https://host").body)
    end

    test "the assembled request meets phase 1's cross-field rules" do
      subject = operation(method: "GET", projections: { payload: [:body, "body"] })

      assert_raises(Dexpace::InvalidArgumentError) do
        subject.build_request(base_url: "https://host", inputs: { payload: "x" })
      end
    end

    # testing/f36a19cd makes a property-style test mandatory for a value object with a
    # parse-constructor invariant. Phase 0's #sample(count:, seed:) is the bounded helper.
    test "any path value produces a URL that re-parses with the expected segment count" do
      subject = operation(template: "/pets/{id}", projections: { id: [:path, "id"] })
      alphabet = ["a", "/", "?", "#", "&", " ", "%", "\xC3\xA5".b, "\xFF".b].freeze

      sample(count: 40, seed: 20_260_907) do |random|
        value = Array.new(random.rand(1..6)) { alphabet.sample(random: random) }.join
        url = subject.build_request(base_url: "https://host/c", inputs: { id: value }).url

        assert_equal(url.to_s, Dexpace::URL.parse!(url.to_s).to_s, "value #{value.inspect}")
        # The base contributes /c, the template /pets/{id}, and a correctly encoded value adds
        # exactly one segment however many slashes it contains: "", "c", "pets", <value>.
        assert_equal(4, url.path.split("/").length,
                     "value #{value.inspect} produced #{url.path.inspect}",)
      end
    end
  end
end
