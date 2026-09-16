# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"
require "stringio"

# HTTP-3, HTTP-46, HTTP-51, BODY-2.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: HTTP-3's
# builder and HTTP-51's one framing routine here, then Framing, Boundary, Quoting and Construction
# below.
class DexpaceMultipartBodyTest < DexpaceTestCase
  # One shared factory set for every class below.
  module Parts
    def part(name: "f", body: Dexpace::Body.bytes("héllo"), **rest)
      Dexpace::MultipartBody::Part.new(name: name, body: body, **rest)
    end

    def drain(body)
      sink = Dexpace::IO::Buffer.new
      body.write_to(sink)
      sink.snapshot
    end
  end
  include Parts

  # ---- HTTP-3: the multipart body is a builder-based model --------------------------------

  # HTTP-3 names "the multipart body" alongside Request, Response, Headers, QueryParams,
  # RequestOptions and RequestConditions: newBuilder() returns a builder PRE-POPULATED with the
  # instance's current fields, so a caller derives a modified copy without restating what did
  # not change. The ID is phase 1's; the subject only exists here.
  test "new_builder returns a builder pre-filled with the body's own fields" do
    original = Dexpace::MultipartBody.new([part(name: "a")], subtype: "mixed")

    derived = original.new_builder.tap { |b| b.parts += [part(name: "b")] }.build

    assert_equal(original.boundary, derived.boundary)
    assert_equal("mixed", derived.subtype)
    assert_equal(%w[a b], derived.parts.map(&:name))
    assert_equal(%w[a], original.parts.map(&:name))
  end

  # HTTP-3's second clause: "the pre-filled builder MUST NOT alias the original's internal
  # collections (each value list is copied)". A shared Array would let a later builder mutation
  # reach back into a frozen body's parts and change the bytes it writes.
  test "the pre-filled builder does not alias the original's parts list" do
    original = Dexpace::MultipartBody.new([part(name: "a")])
    builder = original.new_builder

    builder.parts << part(name: "b")

    refute_same(original.parts, builder.parts)
    assert_equal(%w[a], original.parts.map(&:name))
    assert_equal(1, original.parts.length)
  end

  test "a builder with nothing set builds an empty body with a generated boundary" do
    body = Dexpace::MultipartBody::Builder.new.build

    assert_empty(body.parts)
    assert_equal("form-data", body.subtype)
    assert_equal("--#{body.boundary}--\r\n".b, drain(body))
  end

  # ---- HTTP-51's one shared framing routine ------------------------------------------------

  # THE property this class exists for, stated as a property rather than as three examples: over
  # random part lists the declared length equals the bytes written, because both come from #emit.
  test "the declared length always equals the bytes actually written" do
    sample(count: 48, seed: 20_260_908) do |rng|
      parts = Array.new(rng.rand(1..5)) do |index|
        payload = "é" * rng.rand(0..40)
        filename = rng.rand(2).zero? ? nil : "f#{index}.txt"
        part(name: "p#{index}", body: Dexpace::Body.bytes(payload), filename: filename)
      end
      body = Dexpace::Body.multipart(parts)

      assert_equal(body.content_length, drain(body).bytesize)
    end
  end

  test "the memoised length still equals the bytes written after several writes" do
    body = Dexpace::Body.multipart([part, part(name: "g")])
    declared = body.content_length

    assert_equal(declared, drain(body).bytesize)
    assert_equal(declared, body.content_length)
    assert_equal(declared, drain(body).bytesize)
  end

  # The length query runs the framing routine, and running it against the PART BODIES would make
  # asking for a header value consume them: a part that is single-use but length-known is drained
  # -- and, with close: true, closed -- before the write that was going to send it (P3-29).
  test "the length query does not consume a single-use part, nor close its stream" do
    io = StringIO.new(+"héllo")
    part = part(body: Dexpace::Body.stream(io, content_length: 6, close: true))
    body = Dexpace::Body.multipart([part], boundary: "XyZ")
    declared = body.content_length

    refute_predicate(io, :closed?)
    assert_equal(declared, drain(body).bytesize)
  end

  test "computes the length lazily, so building a body stats nothing" do
    body = Dexpace::Body.multipart([part])

    assert_nil(body.instance_variable_get(:@content_length))
    body.content_length

    refute_nil(body.instance_variable_get(:@content_length))
  end

  # The bytes on the wire, and BODY-2's two conjunctions.
  class FramingTest < DexpaceTestCase
    include Parts

    test "frames each part with the boundary, its headers, a blank line and a trailing CRLF" do
      body = Dexpace::Body.multipart([part(name: "f", body: Dexpace::Body.bytes("AB"))],
                                     boundary: "XyZ",)

      assert_equal(
        "--XyZ\r\nContent-Disposition: form-data; name=\"f\"\r\n\r\nAB\r\n--XyZ--\r\n".b,
        drain(body),
      )
    end

    test "closes the body with the boundary plus two dashes" do
      assert(drain(Dexpace::Body.multipart([part], boundary: "XyZ")).end_with?("--XyZ--\r\n".b))
    end

    test "emits a part's own media type as a Content-Type header" do
      media = Dexpace::MediaType.parse("text/plain; charset=utf-8")
      body = Dexpace::Body.multipart([part(body: Dexpace::Body.bytes("A", media_type: media))],
                                     boundary: "XyZ",)

      assert_includes(drain(body), "Content-Type: text/plain; charset=utf-8".b)
    end

    test "emits a filename and any extra part headers" do
      body = Dexpace::Body.multipart(
        [part(filename: "a.txt", headers: { "X-Note" => "n" })], boundary: "XyZ",
      )

      assert_includes(drain(body), "; filename=\"a.txt\"\r\nX-Note: n\r\n\r\n".b)
    end

    test "delivers BINARY bytes and reports the count it wrote" do
      body = Dexpace::Body.multipart([part], boundary: "XyZ")
      sink = Dexpace::IO::Buffer.new

      assert_equal(drain(body).bytesize, body.write_to(sink))
      assert_equal(::Encoding::BINARY, sink.snapshot.encoding)
    end

    test "is replayable if and only if every part is replayable" do
      replayable = Dexpace::Body.multipart([part, part(name: "g")])
      mixed = Dexpace::Body.multipart(
        [part, part(name: "g", body: Dexpace::Body.stream(StringIO.new(+"a")))],
      )

      assert_predicate(replayable, :replayable?)
      refute_predicate(mixed, :replayable?)
    end

    test "collapses its declared length to the -1 sentinel if any part's length is unknown" do
      mixed = Dexpace::Body.multipart(
        [part, part(name: "g", body: Dexpace::Body.stream(StringIO.new(+"a")))],
      )

      assert_equal(-1, mixed.content_length)
    end

    test "a single-use part makes the body single-use, and it writes once" do
      body = Dexpace::Body.multipart([part(body: Dexpace::Body.chunked(["a"]))], boundary: "X")
      drain(body)

      assert_raises(Dexpace::StreamError) { drain(body) }
    end
  end

  # HTTP-51's boundary grammar.
  class BoundaryTest < DexpaceTestCase
    include Parts

    test "generates a boundary inside RFC 2046's 1-70 bcharsnospace grammar" do
      boundary = Dexpace::Body.multipart([part]).boundary

      assert_operator(boundary.length, :>=, 1)
      assert_operator(boundary.length, :<=, 70)
      assert(boundary.each_char.all? { |c| Dexpace::MultipartBody::BOUNDARY_CHARS.include?(c) })
    end

    test "generates a different boundary every time" do
      boundaries = Array.new(16) { Dexpace::Body.multipart([part]).boundary }

      assert_equal(16, boundaries.uniq.length)
    end

    test "rejects a caller boundary carrying a character outside the grammar" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.multipart([part], boundary: "has space")
      end

      assert_includes(error.message, "bcharsnospace")
    end

    test "rejects an empty boundary and one longer than 70 characters" do
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.multipart([part], boundary: "") }
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.multipart([part], boundary: "a" * 71)
      end
    end

    test "accepts a caller boundary at both ends of the grammar" do
      assert_equal("a", Dexpace::Body.multipart([part], boundary: "a").boundary)
      assert_equal("a" * 70, Dexpace::Body.multipart([part], boundary: "a" * 70).boundary)
      specials = "'()+_,-./:=?"

      assert_equal(specials, Dexpace::Body.multipart([part], boundary: specials).boundary)
    end

    test "carries the boundary into the media type, so a header can name it" do
      body = Dexpace::Body.multipart([part], boundary: "XyZ")

      assert_equal("multipart/form-data; boundary=XyZ", body.media_type.render)
    end

    test "quotes a boundary in the media type when it is not a token" do
      body = Dexpace::Body.multipart([part], boundary: "a(b")

      assert_equal("multipart/form-data; boundary=\"a(b\"", body.media_type.render)
      assert_equal("a(b", body.media_type.parameters["boundary"])
    end
  end

  # HTTP-51's one MUST: quoting and escaping.
  class QuotingTest < DexpaceTestCase
    include Parts

    test "escapes a quote in a parameter value so it cannot close the quoted string early" do
      body = Dexpace::Body.multipart([part(name: 'a"b')], boundary: "XyZ")

      assert_includes(drain(body), 'name="a\\"b"'.b)
    end

    test "escapes a backslash in a parameter value" do
      body = Dexpace::Body.multipart([part(name: "a\\b")], boundary: "XyZ")

      assert_includes(drain(body), 'name="a\\\\b"'.b)
    end

    # A CR or an LF is REJECTED rather than escaped: RFC 7578's quoted-string has no representation
    # for them, and an escaped CRLF is still a CRLF on the wire.
    test "rejects a CR or an LF in a parameter value rather than escaping it" do
      crlf = Dexpace::Body.multipart([part(name: "a\r\nContent-Length: 0")], boundary: "XyZ")
      error = assert_raises(Dexpace::InvalidArgumentError) { drain(crlf) }

      assert_includes(error.message, "CR or LF")
    end

    test "rejects a CR or an LF in a filename the same way" do
      body = Dexpace::Body.multipart([part(filename: "a\nb")], boundary: "XyZ")

      assert_raises(Dexpace::InvalidArgumentError) { drain(body) }
    end

    test "rejects a part header value carrying a byte no header value may carry" do
      body = Dexpace::Body.multipart([part(headers: { "X-Note" => "a\rb" })], boundary: "XyZ")

      assert_raises(Dexpace::InvalidArgumentError) { drain(body) }
    end

    test "the length query rejects the same framing break the write does" do
      body = Dexpace::Body.multipart([part(name: "a\nb")], boundary: "XyZ")

      assert_raises(Dexpace::InvalidArgumentError) { body.content_length }
    end
  end

  # Construction and HTTP-46.
  class ConstructionTest < DexpaceTestCase
    include Parts

    test "rejects anything that is not a Part" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.multipart([Dexpace::Body.bytes("a")])
      end

      assert_includes(error.message, "Part")
    end

    # A subtype carrying a ";" would parse as a subtype plus a smuggled parameter, with #subtype
    # and #media_type disagreeing; one bare token is all a subtype may be.
    test "rejects a subtype that is not one bare token" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.multipart([part], subtype: "form-data;x=1")
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.multipart([part], subtype: "not a subtype")
      end
      assert_equal("mixed", Dexpace::Body.multipart([part], subtype: "mixed").subtype)
    end

    test "rejects nil parts with SEAM-29's one message form" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.multipart(nil) }

      assert_equal("parts is required", error.message)
    end

    test "a Part requires a name and a Dexpace::Body" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::MultipartBody::Part.new(name: nil, body: Dexpace::Body.bytes("a"))
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::MultipartBody::Part.new(name: "f", body: "not a body")
      end
    end

    test "a Part is frozen and delegates replayability and length to its body" do
      one = part(body: Dexpace::Body.bytes("héllo"))

      assert_predicate(one, :frozen?)
      assert_predicate(one, :replayable?)
      assert_equal(6, one.content_length)
    end

    test "has no readable source, because it is a request body" do
      assert_raises(Dexpace::StreamError) { Dexpace::Body.multipart([part]).source }
    end

    test "compares by value over its boundary and its parts" do
      first = Dexpace::Body.multipart([part], boundary: "XyZ")
      same = Dexpace::Body.multipart([part], boundary: "XyZ")
      other = Dexpace::Body.multipart([part], boundary: "AbC")

      assert_equal(first, same)
      refute_equal(first, other)
      assert_equal(first.hash, same.hash)
      assert_equal(part, part)
    end

    # The subtype is the third value-determining fact: same parts, same boundary, a different
    # Content-Type on the wire (review round 0, R0-4).
    test "two bodies that differ only in subtype are different values" do
      form = Dexpace::Body.multipart([part], boundary: "XyZ", subtype: "form-data")
      mixed = Dexpace::Body.multipart([part], boundary: "XyZ", subtype: "mixed")

      refute_equal(form, mixed)
      refute_equal(form.hash, mixed.hash)
      refute_equal(form.media_type, mixed.media_type)
      refute_operator(form, :eql?, mixed)
    end
  end
end
