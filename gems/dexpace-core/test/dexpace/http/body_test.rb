# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/fake_body"
require_relative "../../support/fake_sink"
require_relative "../../support/fake_source"
require "stringio"

# HTTP-36, HTTP-38, HTTP-39, HTTP-52, BODY-1, BODY-10, BODY-13, BODY-25, BODY-30, BODY-32, BODY-35,
# and §10.2's #each.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: the
# contract's defaults and #each here, then Copy, Factories and BufferBounded below.
class DexpaceBodyTest < DexpaceTestCase
  # One shared factory set for every class below.
  module Bodies
    def bare
      Class.new { include Dexpace::Body }.new
    end

    def buffer_of(*strings)
      buffer = Dexpace::IO::Buffer.new
      strings.each { |string| buffer.write(string.b) }
      buffer
    end
  end
  include Bodies

  # ---- the defaults the contract carries (HTTP-36, BODY-1, BODY-35) ------------------------

  test "defaults replayable? to false, because BODY-1 makes replay a property a body earns" do
    refute_predicate(bare, :replayable?)
  end

  test "defaults content_length to the -1 sentinel and never to nil" do
    assert_equal(-1, bare.content_length)
  end

  test "defaults media_type to nil, which HTTP-36 makes nullable" do
    assert_nil(bare.media_type)
  end

  test "raises NotImplementedError when the includer never defined the one hook" do
    error = assert_raises(::NotImplementedError) { bare.write_to(Dexpace::IO::Buffer.new) }

    assert_includes(error.message, "#write_to(sink)")
  end

  # P3-23: the read side has a default too, and it RAISES by name rather than being absent, so
  # the sig/ declaration is true of every Dexpace::Body and a request-body variant reaching
  # Response#body fails as a Dexpace::StreamError and not as a NoMethodError.
  test "defaults source to a named StreamError, because a request body has no read handle" do
    error = assert_raises(Dexpace::StreamError) { bare.source }

    assert_includes(error.message, "HTTP-36")
  end

  test "defaults close to a no-op, because a body owning no transport resource releases nothing" do
    assert_nil(bare.close)
  end

  # HTTP-46's default, right for every variant holding a live stream: identity, all three together.
  test "defaults equality to identity, with eql? and hash agreeing" do
    one = bare
    same = one

    assert_equal(one, same)
    assert(one.eql?(same))
    refute_equal(one, bare)
    refute_equal(one.hash, bare.hash)
  end

  # ---- #each derived from #write_to, once (§10.2, P3-21) ----------------------------------

  test "each yields exactly the chunks the single write produced, tagged BINARY" do
    chunks = []
    encodings = []

    FakeBody.new("hé", "llo").each do |chunk|
      chunks << chunk
      encodings << chunk.encoding
    end

    assert_equal(["hé".b, "llo".b], chunks)
    assert_equal([::Encoding::BINARY] * 2, encodings)
  end

  test "each with no block returns an Enumerator over the same bytes" do
    assert_equal(["hé".b, "llo".b], FakeBody.new("hé", "llo").each.to_a)
  end

  test "each and write_to produce identical bytes, which is what BODY-17 leans on" do
    sink = Dexpace::IO::Buffer.new
    FakeBody.new("hé", "llo").write_to(sink)
    yielded = +"".b
    FakeBody.new("hé", "llo").each { |chunk| yielded << chunk }

    assert_equal(sink.snapshot, yielded)
  end

  # ---- to_replayable (BODY-3/HTTP-37) ------------------------------------------------------

  test "to_replayable returns the same body unchanged when it is already replayable" do
    body = FakeBody.new("a", replayable: true)

    assert_same(body, body.to_replayable)
  end

  test "to_replayable drains a single-use body once into a replayable BufferBody" do
    body = FakeBody.new("hé", "llo")

    materialized = body.to_replayable

    assert_instance_of(Dexpace::BufferBody, materialized)
    assert_predicate(materialized, :replayable?)
    assert_equal(1, body.writes)
  end

  test "to_replayable carries the media type across" do
    media = Dexpace::MediaType.parse("text/plain")

    assert_equal(media, FakeBody.new("a", media_type: media).to_replayable.media_type)
  end

  # HTTP-39/BODY-10, BODY-13, BODY-25: the two private copy routines.
  class CopyTest < DexpaceTestCase
    include Bodies

    test "copy_exactly writes precisely the declared count" do
      source = Dexpace::IO::BufferedSource.of_bytes("0123456789")
      sink = Dexpace::IO::Buffer.new

      assert_equal(4, bare.send(:copy_exactly, source, sink, 4))
      assert_equal("0123", sink.snapshot)
    end

    test "copy_exactly treats a declared length of zero as a legitimate empty write" do
      sink = FakeSink.new

      assert_equal(0, bare.send(:copy_exactly, FakeSource.new, sink, 0))
      assert_empty(sink.writes)
    end

    test "copy_exactly raises naming delivered-of-total when the source ends early" do
      source = Dexpace::IO::BufferedSource.of_bytes("012")
      error = assert_raises(Dexpace::StreamError) do
        bare.send(:copy_exactly, source, Dexpace::IO::Buffer.new, 10)
      end

      assert_includes(error.message, "3")
      assert_includes(error.message, "10")
    end

    test "copy_exactly treats a zero read for a positive count as a contract violation" do
      error = assert_raises(Dexpace::StreamError) do
        bare.send(:copy_exactly, FakeSource.new(0), Dexpace::IO::Buffer.new, 4)
      end

      assert_includes(error.message, "IO-17")
    end

    test "copy_exactly does not spin when the source keeps returning zero" do
      source = FakeSource.new(0, 0, 0)
      assert_raises(Dexpace::StreamError) do
        bare.send(:copy_exactly, source, Dexpace::IO::Buffer.new, 4)
      end

      assert_equal(1, source.calls.length)
    end

    test "copy_exactly detects a short write from the sink and names transferred-of-total" do
      source = Dexpace::IO::BufferedSource.of_bytes("0123456789")
      error = assert_raises(Dexpace::StreamError) do
        bare.send(:copy_exactly, source, FakeSink.new(2), 4)
      end

      assert_includes(error.message, "2")
      assert_includes(error.message, "4")
    end

    # The sink is asked for whatever the source's own read returned, never a size this layer
    # invented (plan decision 4), so an upstream's chunk boundaries survive to BODY-17's mirror.
    test "copy_exactly forwards the source's own chunk boundaries to the sink" do
      sink = FakeSink.new
      bare.send(:copy_exactly, FakeSource.new("hé", "llo"), sink, 6)

      assert_equal(["hé".b, "llo".b], sink.writes)
    end

    test "emit_exactly retags a frozen non-BINARY String without raising FrozenError" do
      sink = FakeSink.new

      assert_equal(6, bare.send(:emit_exactly, sink, "héllo"))
      assert_equal(::Encoding::BINARY, sink.writes.first.encoding)
    end

    test "emit_exactly writes nothing for an empty String and reports zero" do
      sink = FakeSink.new

      assert_equal(0, bare.send(:emit_exactly, sink, ""))
      assert_empty(sink.writes)
    end
  end

  # HTTP-38/BODY-35's factories, one place.
  class FactoriesTest < DexpaceTestCase
    include Bodies

    test "bytes and string both build a replayable BytesBody, which HTTP-38 classifies alike" do
      assert_instance_of(Dexpace::BytesBody, Dexpace::Body.bytes("a"))
      assert_instance_of(Dexpace::BytesBody, Dexpace::Body.string("a"))
    end

    test "string encodes eagerly, so a later mutation of the caller's String cannot reach it" do
      text = +"héllo"
      body = Dexpace::Body.string(text)
      text << " more"

      assert_equal(6, body.content_length)
    end

    test "string encodes into the named charset, so the byte count is that charset's" do
      body = Dexpace::Body.string("héllo", encoding: ::Encoding::ISO_8859_1)

      assert_equal(5, body.content_length)
    end

    test "string rejects a non-String rather than calling to_s on it" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.string(42) }

      assert_includes(error.message, "Integer")
    end

    test "bytes rejects a non-String rather than coercing it" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.bytes(:sym) }

      assert_includes(error.message, "Symbol")
    end

    test "the eight factories cover seven classes, with string and bytes sharing one" do
      assert_instance_of(Dexpace::BufferBody, Dexpace::Body.buffer(buffer_of("a")))
      assert_instance_of(Dexpace::ChunkedBody, Dexpace::Body.chunked(["a"]))
      assert_instance_of(Dexpace::FormBody, Dexpace::Body.form([%w[a b]]))
      assert_instance_of(Dexpace::StreamBody, Dexpace::Body.stream(StringIO.new(+"a")))
    end
  end

  # BODY-30/HTTP-52's bounded replayable copy, BODY-32's cap rules a second time, and BODY-31 as
  # the status-blind negative guarantee. The drain is through #source (P3-23's write-side half),
  # so the suite runs over the three bodies that can occupy Response#body -- a ResponseBody, a
  # ResponseLoggingBody in both regimes, and a BufferBody -- and over two #source-answering
  # doubles for the close counter and the mid-drain failure.
  class BufferBoundedTest < DexpaceTestCase
    include Bodies

    def response_body(content = "héllo", **rest)
      Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content), **rest)
    end

    def read_twice(copy)
      Array.new(2) do
        sink = Dexpace::IO::Buffer.new
        copy.write_to(sink)
        sink.snapshot
      end
    end

    test "returns a replayable buffer-backed body readable more than once" do
      copy = Dexpace::Body.buffer_bounded(response_body("héllo"), cap: 64)

      assert_instance_of(Dexpace::BufferBody, copy)
      assert_predicate(copy, :replayable?)
      assert_equal(["héllo".b] * 2, read_twice(copy))
    end

    test "drains a ResponseBody through its source and closes it inside the drain's scope" do
      body = response_body("héllo")
      copy = Dexpace::Body.buffer_bounded(body, cap: 64)

      assert_predicate(body, :closed?)
      assert_equal("héllo".b, read_twice(copy).first)
    end

    test "drains a fits-cap ResponseLoggingBody, whose #write_to raises by design" do
      wrapper = Dexpace::ResponseLoggingBody.new(response_body("héllo"), preview_bytes: 64)
      copy = Dexpace::Body.buffer_bounded(wrapper, cap: 64)

      assert_equal(["héllo".b] * 2, read_twice(copy))
      assert_predicate(wrapper, :closed?)
    end

    test "drains an over-cap ResponseLoggingBody, prefix and live tail, and closes it" do
      wrapper = Dexpace::ResponseLoggingBody.new(response_body("0123456789"), preview_bytes: 4)
      copy = Dexpace::Body.buffer_bounded(wrapper, cap: 64)

      assert_equal(["0123456789".b] * 2, read_twice(copy))
      assert_predicate(wrapper, :closed?)
    end

    test "drains a BufferBody through a fresh view and leaves the original readable" do
      original = Dexpace::BufferBody.new(buffer_of("héllo"))
      copy = Dexpace::Body.buffer_bounded(original, cap: 64)

      assert_equal(["héllo".b] * 2, read_twice(copy))
      assert_equal(["héllo".b] * 2, read_twice(original))
    end

    test "closes the original inside the drain's scope" do
      delegate = SourceDouble.new("body")
      Dexpace::Body.buffer_bounded(delegate, cap: 64)

      assert_equal(1, delegate.closes)
    end

    test "still closes the original when the drain raises" do
      delegate = SourceDouble.new("ab", Dexpace::StreamError.new("boom"))
      assert_raises(Dexpace::StreamError) { Dexpace::Body.buffer_bounded(delegate, cap: 64) }

      assert_equal(1, delegate.closes)
    end

    test "carries the original body's media type onto the copy" do
      media = Dexpace::MediaType.parse("application/problem+json")
      copy = Dexpace::Body.buffer_bounded(response_body("a", media_type: media), cap: 8)

      assert_equal(media, copy.media_type)
    end

    test "truncates markerlessly at the cap" do
      copy = Dexpace::Body.buffer_bounded(response_body("0123456789"), cap: 4)

      assert_equal("0123".b, read_twice(copy).first)
      assert_equal(4, copy.content_length)
    end

    test "rejects a negative cap and clamps a huge one to the ceiling" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.buffer_bounded(response_body("a"), cap: -1)
      end
      copy = Dexpace::Body.buffer_bounded(response_body("a"), cap: ::Float::INFINITY)

      assert_equal(1, copy.content_length)
    end

    test "a zero cap buffers nothing and still closes the original" do
      delegate = SourceDouble.new("body")
      copy = Dexpace::Body.buffer_bounded(delegate, cap: 0)

      assert_equal(0, copy.content_length)
      assert_equal(1, delegate.closes)
    end

    # BODY-30's default is fixed by the requirement's own text, so it takes no keyword anywhere.
    test "MAX_BUFFERED_ERROR_BODY_BYTES is 1 MiB and is the default cap" do
      assert_equal(1024 * 1024, Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES)
      assert_equal(
        [%i[req body], %i[key cap]], Dexpace::Body.method(:buffer_bounded).parameters,
      )
    end

    # THE allocating test, and it runs on every matrix row on purpose: it is the only place the
    # 1 MiB bound is exercised for real, and "the bytes beyond the cap are not read" is a claim
    # about a body larger than the cap that no smaller fixture can make.
    test "over a body larger than the cap, stops reading rather than discarding" do
      oversized = OversizedBody.new(2 * Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES)

      copy = Dexpace::Body.buffer_bounded(oversized)

      assert_equal(Dexpace::Body::MAX_BUFFERED_ERROR_BODY_BYTES, copy.content_length)
      assert_operator(oversized.yielded_bytes, :<, oversized.total)
      assert_equal(1, oversized.closes)
    end

    # BODY-31 is a CROSS-REFERENCE row: the predicate is phase 1's Status#error? and the step that
    # reads it is phase 4's. The body layer's whole contribution is this negative guarantee, and it
    # is asserted mechanically rather than described, because "we did not write a status check" is
    # exactly the kind of claim that stops being true one refactor later.
    test "takes a body and a cap, and no status of any kind" do
      names = Dexpace::Body.method(:buffer_bounded).parameters.map(&:last)

      assert_equal(%i[body cap], names)
    end

    test "no executable line of the body module mentions a status" do
      path = File.expand_path("../../../lib/dexpace/http/body.rb", __dir__)
      code = File.readlines(path).reject { |line| line.strip.start_with?("#") }

      refute_match(/\bstatus\b/, code.join)
    end

    # A minimal response-body-shaped delegate: #source, #media_type, #content_length and #close --
    # the surface buffer_bounded uses -- with a close counter and a scriptable mid-drain failure.
    class SourceDouble
      include Dexpace::Body

      attr_reader :closes, :source

      def initialize(*script)
        @source = FakeSource.new(*script)
        @closes = 0
      end

      def close
        @closes += 1
        nil
      end
    end

    # A source that yields 64 KiB blocks on demand and counts what was actually pulled, so "not
    # read" is measurable; it never touches a BufferedSource's own buffer beyond one block.
    class OversizedBody
      include Dexpace::Body

      CHUNK = 64 * 1024

      attr_reader :total, :yielded_bytes, :closes

      def initialize(total)
        @total = total
        @yielded_bytes = 0
        @closes = 0
        @source = nil
      end

      def content_length = @total

      def source
        @source ||= Dexpace::IO::BufferedSource.over(blocks)
      end

      def close
        @closes += 1
        nil
      end

      private

      def blocks
        block = ("x" * CHUNK).b.freeze
        Enumerator.new do |yielder|
          (@total / CHUNK).times do
            @yielded_bytes += CHUNK
            yielder << block
          end
        end
      end
    end
  end
end
