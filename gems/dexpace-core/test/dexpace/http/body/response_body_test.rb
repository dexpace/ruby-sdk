# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"
require_relative "../../../support/fake_sink"
require "stringio"

# HTTP-41, HTTP-46, BODY-14, BODY-15, BODY-32, BODY-33.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: BODY-14
# and BODY-15 here, then Preview and Construction below.
class DexpaceResponseBodyTest < DexpaceTestCase
  # One shared factory set for every class below.
  module Bodies
    def body(content = "héllo", **rest)
      Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content), **rest)
    end

    def over(io, **rest)
      Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.wrapping(io), **rest)
    end
  end
  include Bodies

  # ---- BODY-14: single-use, and the SAME handle every time ---------------------------------

  test "returns the same underlying handle every time, never a fresh replay" do
    subject = body

    assert_same(subject.source, subject.source)
  end

  test "is not replayable, because a response body's bytes are gone once consumed" do
    refute_predicate(body, :replayable?)
  end

  test "writes once and raises on a second write rather than emitting zero bytes" do
    subject = body
    sink = Dexpace::IO::Buffer.new
    subject.write_to(sink)
    error = assert_raises(Dexpace::StreamError) { subject.write_to(Dexpace::IO::Buffer.new) }

    assert_equal("héllo".b, sink.snapshot)
    assert_includes(error.message, "BODY-6")
  end

  test "to_replayable materialises it once into a repeatable BufferBody" do
    materialized = body.to_replayable
    first = Dexpace::IO::Buffer.new
    second = Dexpace::IO::Buffer.new
    materialized.write_to(first)
    materialized.write_to(second)

    assert_equal("héllo".b, first.snapshot)
    assert_equal("héllo".b, second.snapshot)
  end

  test "copies exactly the declared count when it has one" do
    subject = body("0123456789", content_length: 4)
    sink = Dexpace::IO::Buffer.new
    subject.write_to(sink)

    assert_equal("0123".b, sink.snapshot)
  end

  # ---- BODY-15: idempotent close that releases the transport resource ----------------------

  test "close releases the underlying source" do
    source = Dexpace::IO::BufferedSource.of_bytes("héllo")
    subject = Dexpace::ResponseBody.new(source: source)
    subject.close

    assert_predicate(source, :closed?)
    assert_predicate(subject, :closed?)
  end

  test "close is idempotent, and the second close releases nothing a second time" do
    io = StringIO.new(+"héllo")
    subject = over(io)
    subject.close
    subject.close

    assert_predicate(io, :closed?)
  end

  test "close makes no assumption that the body was read" do
    io = StringIO.new(+"héllo")
    over(io).close

    assert_predicate(io, :closed?)
  end

  test "the block form closes on a normal return and returns the block's value" do
    io = StringIO.new(+"héllo")
    source = Dexpace::IO::BufferedSource.wrapping(io)
    result = Dexpace::ResponseBody.new(source: source, &:content_length)

    assert_equal(-1, result)
    assert_predicate(io, :closed?)
  end

  test "the block form closes on any exit path, including a raise" do
    io = StringIO.new(+"héllo")
    source = Dexpace::IO::BufferedSource.wrapping(io)
    assert_raises(Dexpace::StreamError) do
      Dexpace::ResponseBody.new(source: source) { raise Dexpace::StreamError, "boom" }
    end

    assert_predicate(io, :closed?)
  end

  test "a read on the source after close raises ClosedError, since a real stream is not exempt" do
    subject = over(StringIO.new(+"héllo"))
    subject.close

    assert_raises(Dexpace::ClosedError) { subject.source.read }
  end

  # BODY-33 and BODY-32: the non-consuming capped preview.
  class PreviewTest < DexpaceTestCase
    include Bodies

    test "preview reads from a fresh peek view and does not advance the primary read path" do
      subject = body("0123456789")

      assert_equal("0123".b, subject.preview(cap: 4))
      assert_equal("0123".b, subject.preview(cap: 4))
      sink = Dexpace::IO::Buffer.new
      subject.write_to(sink)

      assert_equal("0123456789".b, sink.snapshot)
    end

    test "preview returns an empty BINARY result when the source is exhausted" do
      subject = body("abc")
      subject.write_to(Dexpace::IO::Buffer.new)
      preview = subject.preview(cap: 8)

      assert_equal("".b, preview)
      assert_equal(::Encoding::BINARY, preview.encoding)
    end

    test "preview returns whatever bytes exist without requiring exactly the cap" do
      assert_equal("abc".b, body("abc").preview(cap: 64))
    end

    test "preview of zero bytes is empty and reads nothing" do
      assert_equal("".b, body("abc").preview(cap: 0))
    end

    test "preview rejects a negative cap" do
      error = assert_raises(Dexpace::InvalidArgumentError) { body.preview(cap: -1) }

      assert_includes(error.message, "negative")
    end

    test "preview silently clamps a cap above the ceiling, never up" do
      over_ceiling = Dexpace::IO::MAX_MATERIALIZED_BYTES + 1

      assert_equal("abc".b, body("abc").preview(cap: over_ceiling))
      assert_equal("abc".b, body("abc").preview(cap: ::Float::INFINITY))
    end

    # BODY-32 as a property: negative raises, and every accepted cap returns at most
    # min(cap, ceiling, available) bytes.
    test "the clamp holds over negative, zero, huge and ceiling+1 caps" do
      ceiling = Dexpace::IO::MAX_MATERIALIZED_BYTES
      sample(count: 40, seed: 20_260_908) do |rng|
        cap = [-rng.rand(1..8), 0, rng.rand(0..12), ceiling + 1, ceiling * 2].sample(random: rng)
        subject = body("0123456789")
        if cap.negative?
          assert_raises(Dexpace::InvalidArgumentError) { subject.preview(cap: cap) }
        else
          assert_operator(subject.preview(cap: cap).bytesize, :<=, [cap, ceiling, 10].min)
        end
      end
    end

    test "preview closes every view it takes, so repeated previews do not grow the registry" do
      source = Dexpace::IO::BufferedSource.of_bytes("0123456789")
      subject = Dexpace::ResponseBody.new(source: source)
      20.times { subject.preview(cap: 4) }

      assert_equal(0, source.instance_variable_get(:@dexpace_views).length)
    end

    test "preview after close raises ClosedError rather than serving stale bytes" do
      subject = body
      subject.close

      assert_raises(Dexpace::ClosedError) { subject.preview(cap: 4) }
    end
  end

  # Construction and HTTP-46.
  class ConstructionTest < DexpaceTestCase
    include Bodies

    test "rejects a source that does not respond to read_into" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::ResponseBody.new(source: Object.new)
      end

      assert_includes(error.message, "#read_into")
    end

    test "rejects a content_length below the -1 sentinel" do
      assert_raises(Dexpace::InvalidArgumentError) { body(content_length: -2) }
    end

    test "carries its media type and declared length" do
      media = Dexpace::MediaType.parse("text/plain")
      subject = body("héllo", media_type: media, content_length: 6)

      assert_equal(media, subject.media_type)
      assert_equal(6, subject.content_length)
    end

    test "compares by identity, because two live sources are two values" do
      subject = body
      same = subject

      assert_equal(subject, same)
      refute_equal(subject, body)
    end
  end
end
