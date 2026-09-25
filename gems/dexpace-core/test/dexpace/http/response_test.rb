# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/fake_response_body"

# HTTP-3, HTTP-4, HTTP-5, HTTP-6, HTTP-11, HTTP-19. The `.build` coercion and rejection cases have
# their own nested group, BuildTest, so the file keeps one top-level suite per lib file; phase
# 3b's three body readers (HTTP-41, HTTP-42, HTTP-43, BODY-16) are the nested groups below it.
class DexpaceResponseTest < DexpaceTestCase
  def response(status: Dexpace::Status::OK)
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = status
    builder.build
  end

  def request
    builder = Dexpace::Request.builder
    builder.url = "https://example.test/"
    builder.build
  end

  test "carries exactly request, protocol, status, reason, headers and body" do
    assert_equal(%i[request protocol status reason headers body], response.to_h.keys)
    assert_equal(request, response.request)
    assert_equal(Dexpace::Protocol::HTTP_1_1, response.protocol)
    assert_equal(Dexpace::Status::OK, response.status)
  end

  test "requires the request, the protocol and the status, naming the missing field" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Response.builder.build }

    assert_equal("request is required", error.message)
  end

  test "names the missing status when only that is absent" do
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    error = assert_raises(Dexpace::InvalidArgumentError) { builder.build }

    assert_equal("status is required", error.message)
  end

  test "names the missing protocol when only that is absent" do
    builder = Dexpace::Response.builder
    builder.request = request
    builder.status = 200
    error = assert_raises(Dexpace::InvalidArgumentError) { builder.build }

    assert_equal("protocol is required", error.message)
  end

  test "carries an optional reason phrase and an optional body, and empty headers by default" do
    built = response

    assert_nil(built.reason)
    assert_nil(built.body)
    assert_predicate(built.headers, :empty?)
    with_reason = built.new_builder
    with_reason.reason = "OK"
    with_reason.body = "payload"

    assert_equal("OK", with_reason.build.reason)
    assert_equal("payload", with_reason.build.body)
  end

  # HTTP-19: the default is the INBOUND empty, so deriving from a header-less response yields a
  # builder that still accepts obs-text rather than one that refuses it.
  test "defaults its headers to the inbound empty, so a derived builder stays lenient" do
    derived = response.headers.new_builder

    assert_same(Dexpace::Headers::EMPTY_INBOUND, response.headers)
    assert_equal(:inbound, response.headers.direction)
    lenient = derived.add("Content-Disposition", "v\xC3\xA5lue").build

    assert_equal(["v\xC3\xA5lue"], lenient["Content-Disposition"])
  end

  test "derives its classification from its status rather than restating the ranges" do
    assert_predicate(response, :success?)
    assert_predicate(response(status: Dexpace::Status.of(101)), :informational?)
    assert_predicate(response(status: Dexpace::Status.of(302)), :redirect?)
    assert_predicate(response(status: Dexpace::Status.of(404)), :client_error?)
    assert_predicate(response(status: Dexpace::Status.of(503)), :server_error?)
    assert_predicate(response(status: Dexpace::Status.of(404)), :error?)
    refute_predicate(response, :error?)
  end

  test "is frozen and derives without aliasing" do
    built = response
    derived = built.new_builder
    derived.status = Dexpace::Status::NOT_FOUND
    derived.headers = Dexpace::Headers.inbound_builder.add("X-A", "1").build

    assert_predicate(built, :frozen?)
    assert_equal(Dexpace::Status::OK, built.status)
    assert_predicate(built.headers, :empty?)
    assert_equal(Dexpace::Status::NOT_FOUND, derived.build.status)
    assert_equal(["1"], derived.build.headers["X-A"])
  end

  test "with re-validates, so a derived response cannot carry a status that is not a code" do
    # A String and not 600 or 1000: phase 10 made Status total over every Integer (HTTP-10).
    assert_raises(Dexpace::InvalidArgumentError) { response.with(status: "404") }
    assert_raises(Dexpace::InvalidArgumentError) { response.with(protocol: nil) }
    assert_equal(Dexpace::Status::NOT_FOUND, response.with(status: 404).status)
  end

  test "is Ractor-shareable, like the request it carries" do
    assert(Ractor.shareable?(response))
  end

  # XCUT-15: the reason phrase is a caller-supplied String, so the model owns a frozen copy
  # rather than the caller's object -- otherwise a mutation after build would change the model
  # in place, and a Response carrying a live String is not shareable either.
  test "owns a frozen copy of the reason, so the caller's String cannot reach the model" do
    reason = +"OK"
    builder = response.new_builder
    builder.reason = reason
    built = builder.build
    reason << " (mutated after build)"

    assert_equal("OK", built.reason)
    refute_same(reason, built.reason)
    assert_predicate(built.reason, :frozen?)
    assert(Ractor.shareable?(built))
  end

  # HTTP-4: what `.build` coerces and what it refuses, whichever path reached it. Nested so the
  # file keeps one top-level suite per lib file.
  class BuildTest < DexpaceTestCase
    def request
      builder = Dexpace::Request.builder
      builder.url = "https://example.test/"
      builder.build
    end

    def response(status: Dexpace::Status::OK)
      builder = Dexpace::Response.builder
      builder.request = request
      builder.protocol = Dexpace::Protocol::HTTP_1_1
      builder.status = status
      builder.build
    end

    test "build coerces a protocol identifier and a status code into their types" do
      builder = Dexpace::Response.builder
      builder.request = request
      builder.protocol = "HTTP/2.0"
      builder.status = 404
      built = builder.build

      assert_equal(Dexpace::Protocol::HTTP_2, built.protocol)
      assert_equal(Dexpace::Status::NOT_FOUND, built.status)
      assert_predicate(built, :client_error?)
    end

    test "build rejects a protocol, a status, a request and headers it cannot coerce" do
      assert_raises(Dexpace::InvalidArgumentError) { response(status: "200") } # every Integer maps
      builder = Dexpace::Response.builder
      builder.request = request
      builder.protocol = "spdy/3"
      builder.status = Dexpace::Status::OK

      assert_raises(Dexpace::InvalidArgumentError) { builder.build }
      assert_raises(Dexpace::InvalidArgumentError) { builder.request = "not a request" }
      assert_raises(Dexpace::InvalidArgumentError) { builder.headers = {} }
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Response.build(
          request: "x", protocol: "http/1.1", status: 200, headers: Dexpace::Headers::EMPTY_INBOUND,
        )
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Response.build(request: request, protocol: "http/1.1", status: 200, headers: {})
      end
    end

    # A non-String reason is a caller mistake in an argument, so it fails with the SDK's error
    # rather than surfacing later as a NoMethodError from whatever first reads it.
    test "build rejects a reason that is not a String, whichever path reached it" do
      assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Response.build(
          request: request, protocol: "http/1.1", status: 200,
          headers: Dexpace::Headers::EMPTY_INBOUND, reason: :ok,
        )
      end
      assert_raises(Dexpace::InvalidArgumentError) { response.with(reason: 200) }
      assert_equal("Not Found", response.with(reason: "Not Found").reason)
    end
  end

  # HTTP-41, HTTP-42, HTTP-43, BODY-16: the three methods phase 3b adds. One shared factory set
  # for the groups below.
  module Readers
    # Sets Encoding.default_internal for the duration of the block and restores it, with the two
    # assignments -- and ONLY those -- made outside $VERBOSE.
    #
    # This helper exists because `Encoding.default_internal = x` emits `warning: setting
    # Encoding.default_internal` under `ruby -w`, and DexpaceTestCase's Warning.warn override turns
    # every warning into a failure (NFR-6). Verified on 3.2.11, 3.4.10 and 4.0.6: without the two
    # narrow suppressions BOTH the set and the restore raise, and with them `-w` stays live for
    # everything the block runs -- which is checked below rather than assumed.
    def with_default_internal(encoding)
      previous = ::Encoding.default_internal
      verbose = $VERBOSE
      begin
        $VERBOSE = nil
        ::Encoding.default_internal = encoding
        $VERBOSE = verbose
        yield
      ensure
        $VERBOSE = nil
        ::Encoding.default_internal = previous
        $VERBOSE = verbose
      end
    end

    def response(body)
      request = Dexpace::Request.builder
      request.url = "https://example.test/"
      builder = Dexpace::Response.builder
      builder.request = request.build
      builder.protocol = Dexpace::Protocol::HTTP_1_1
      builder.status = Dexpace::Status.of(200)
      builder.body = body
      builder.build
    end

    def response_body(bytes, media_type: nil)
      Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(bytes),
                                media_type: media_type,)
    end

    def media(text) = Dexpace::MediaType.parse(text)
  end

  # HTTP-43: close.
  class CloseTest < DexpaceTestCase
    include Readers

    test "close forwards to the body" do
      body = response_body("héllo")
      response(body).close

      assert_predicate(body, :closed?)
    end

    test "a bodyless close is a no-op rather than a failure" do
      assert_nil(response(nil).close)
    end

    test "close is idempotent, with the idempotence living in the body's own latch" do
      body = response_body("héllo")
      subject = response(body)
      subject.close
      subject.close

      assert_predicate(body, :closed?)
    end

    # The default is a RAISE and not an absent method, so a request-body variant that reaches
    # Response#body fails by name rather than with a NoMethodError, and the sig/ declaration stays
    # true of every Dexpace::Body (P3-23). Its #close is the no-op, so the close itself succeeds.
    test "a request-body variant in Response#body fails by name rather than with a NoMethodError" do
      subject = response(Dexpace::Body.bytes("héllo"))
      error = assert_raises(Dexpace::StreamError) { subject.body_bytes }

      assert_includes(error.message, "Dexpace::BytesBody")
      assert_nil(subject.close)
    end
  end

  # HTTP-42: THE decode boundary. Every encoding test here uses NON-ASCII content on purpose: an
  # ASCII-only fixture passes under exactly the bug these three steps prevent.
  class DecodeTest < DexpaceTestCase
    include Readers

    test "decodes UTF-8 bytes declared UTF-8 without mangling them" do
      subject = response(response_body("héllo", media_type: media("text/plain; charset=utf-8")))

      assert_equal("héllo", subject.body_string)
    end

    # The retag is the step design §3.1's recipe omits. Without it, from BINARY every byte >= 0x80
    # is undefined in the SOURCE encoding and #encode replaces it: "café".b.encode(UTF_8, ...) is
    # "caf" plus TWO replacement characters, on all three interpreters.
    test "does not replace every non-ASCII byte, which the retag-less recipe does" do
      decoded = response(
        response_body("café", media_type: media("text/plain; charset=utf-8")),
      ).body_string

      assert_equal("café", decoded)
      refute_includes(decoded, "�")
    end

    test "defaults to UTF-8 when no charset is declared" do
      subject = response(response_body("héllo", media_type: media("text/plain")))

      assert_equal(::Encoding::UTF_8, subject.body_string.encoding)
    end

    test "defaults to UTF-8 when there is no media type at all" do
      assert_equal("héllo", response(response_body("héllo")).body_string)
    end

    # MediaType#charset already returns nil for a charset this Ruby does not know, so Encoding.find
    # cannot raise here and HTTP-42's fallback needs no second validation.
    test "falls back to UTF-8 when the declared charset is unknown to this Ruby" do
      subject = response(
        response_body("héllo", media_type: media("text/plain; charset=x-not-a-charset")),
      )

      assert_equal("héllo", subject.body_string)
    end

    test "honours a declared ISO-8859-1 charset" do
      subject = response(
        response_body("caf\xE9".b, media_type: media("text/plain; charset=iso-8859-1")),
      )
      decoded = subject.body_string

      assert_equal(::Encoding::ISO_8859_1, decoded.encoding)
      assert_equal("café", decoded.encode(::Encoding::UTF_8))
    end

    test "scrubs rather than raises when the bytes do not match the declared charset" do
      subject = response(
        response_body("caf\xE9".b, media_type: media("text/plain; charset=utf-8")),
      )
      decoded = subject.body_string

      assert_predicate(decoded, :valid_encoding?)
      assert_includes(decoded, "�")
    end

    test "returns nil for a bodyless response" do
      assert_nil(response(nil).body_string)
      assert_nil(response(nil).body_bytes)
    end
  end

  # HTTP-42 against the host's Encoding.default_internal, and as a property.
  class DecodeGlobalTest < DexpaceTestCase
    include Readers

    # THE test that stands between the correct recipe and a silent revert to §3.1's. A target-less
    # #encode converts to Encoding.default_internal, a process global the HOST sets -- so a decode
    # that omits its target returns whatever the host asked for and destroys the payload on the way.
    test "the decoded result does not depend on the host's Encoding.default_internal" do
      with_default_internal(::Encoding::ISO_8859_1) do
        subject = response(response_body("héllo", media_type: media("text/plain; charset=utf-8")))
        decoded = subject.body_string

        assert_equal(::Encoding::UTF_8, decoded.encoding)
        assert_equal("héllo", decoded)
      end
    end

    # Against the AMBIENT $VERBOSE, not against `true`: under `-w` that is true and the assertion
    # is the suppression check this test exists for, and running the file without `-w` then still
    # passes rather than failing for the wrong reason (Global Constraints: every test passes
    # alone).
    test "the default_internal helper leaves the ambient $VERBOSE live inside the block" do
      ambient = $VERBOSE
      inside = :unset
      with_default_internal(::Encoding::ISO_8859_1) { inside = $VERBOSE }

      assert_equal(ambient, inside)
      assert_nil(::Encoding.default_internal)
    end

    # HTTP-42 as a property: over random bytes and a small charset set, with a hostile
    # default_internal for half the runs, the result is always valid_encoding? and always tagged
    # with the resolved charset.
    test "the decode holds over random bytes and charsets, with a hostile default_internal" do
      charsets = ["utf-8", "iso-8859-1", "us-ascii", nil]
      sample(count: 48, seed: 20_260_908) do |rng|
        bytes = Array.new(rng.rand(0..24)) { rng.rand(0x80..0xFF).chr }.join.b
        charset = charsets.sample(random: rng)
        type = charset.nil? ? media("text/plain") : media("text/plain; charset=#{charset}")
        expected = charset.nil? ? ::Encoding::UTF_8 : ::Encoding.find(charset)
        hostile = rng.rand(2).zero?

        check = lambda do
          decoded = response(response_body(bytes, media_type: type)).body_string

          assert_equal(expected, decoded.encoding)
          assert_predicate(decoded, :valid_encoding?)
        end
        hostile ? with_default_internal(::Encoding::ISO_8859_1, &check) : check.call
      end
    end
  end

  # P3-23: every body a Response can hold answers #source and #close. Response#close,
  # #body_string and #body_bytes are written against those two, and the body BODY-30/HTTP-52 puts
  # in an error response is a BufferBody; a suite that only ever builds a Response over a bare
  # ResponseBody cannot see that, and phase 4 would be the first to.
  class SurfaceTest < DexpaceTestCase
    include Readers

    # BODY-30's own two-step sentence as one test -- decode it, THEN snapshot it -- after the
    # close BODY-16 performs, which fails if #close ever stops being a no-op on a BufferBody and
    # fails if #source ever stops handing out a fresh view.
    test "a Response carrying the bounded error copy decodes, then snapshots, then closes" do
      copy = Dexpace::Body.buffer_bounded(
        response_body("héllo", media_type: media("text/plain; charset=utf-8")), cap: 64,
      )
      subject = response(copy)

      assert_equal("héllo", subject.body_string)
      assert_equal("héllo".b, response(copy).body_bytes)
      assert_nil(response(copy).close)
      assert_equal("héllo".b, copy.source.read)
    end

    test "a Response carrying a fits-cap response-logging wrapper decodes and closes" do
      delegate = response_body("héllo", media_type: media("text/plain; charset=utf-8"))
      wrapper = Dexpace::ResponseLoggingBody.new(delegate, preview_bytes: 64)

      assert_equal("héllo", response(wrapper).body_string)
      assert_predicate(wrapper, :closed?)
      assert_equal("héllo".b, wrapper.snapshot)
    end

    test "a Response carrying an over-cap response-logging wrapper decodes the whole body" do
      delegate = response_body("héllo wörld", media_type: media("text/plain; charset=utf-8"))
      wrapper = Dexpace::ResponseLoggingBody.new(delegate, preview_bytes: 4)

      assert_equal("héllo wörld", response(wrapper).body_string)
      assert_predicate(wrapper, :closed?)
      assert_predicate(delegate, :closed?)
      assert_equal("hél".b[0, 4], wrapper.snapshot)
    end

    # The handle #source returns is a fresh #peek view on a BufferBody and on a fits-cap wrapper,
    # and neither body's #close reaches it, so the readers are the only thing that can deregister
    # it (review round 0, R0-1). Twenty reads, zero views left: the same pin
    # response_body_test.rb puts on #preview.
    test "the readers close the view they take from a BufferBody, leaving no view behind" do
      copy = Dexpace::Body.buffer_bounded(response_body("héllo"), cap: 64)
      10.times { response(copy).body_string }
      10.times { response(copy).body_bytes }

      assert_equal(0, views(copy.instance_variable_get(:@buffer)))
      assert_equal("héllo".b, copy.source.read)
    end

    test "the readers close the view they take from a fits-cap logging wrapper" do
      wrapper = Dexpace::ResponseLoggingBody.new(response_body("héllo"), preview_bytes: 64)
      10.times { response(wrapper).body_string }
      10.times { response(wrapper).body_bytes }

      assert_equal(0, views(wrapper.instance_variable_get(:@buffer)))
    end

    # Over-cap, the handle is the composite, whose close is the Tail's: it deregisters the prefix
    # view the Tail took and reaches the wrapper's one close-once guard.
    test "the readers close the over-cap composite, deregistering its prefix view" do
      wrapper = Dexpace::ResponseLoggingBody.new(response_body("0123456789"), preview_bytes: 4)
      response(wrapper).body_bytes

      assert_equal(0, views(wrapper.instance_variable_get(:@buffer)))
      assert_predicate(wrapper, :closed?)
    end

    # The wrapper over the OTHER body that can sit beneath it: a BufferBody answers #source with a
    # fresh view per call, so a wrapper that asked more than once delivered the prefix twice and
    # then the whole body through this reader, and left the views it read from registered (review
    # round 1, R1-1).
    test "the readers deliver an over-cap wrapper over a BufferBody once, leaving no view" do
      copy = Dexpace::Body.buffer_bounded(response_body("0123456789"), cap: 64)
      wrapper = Dexpace::ResponseLoggingBody.new(copy, preview_bytes: 4)

      assert_equal("0123456789".b, response(wrapper).body_bytes)
      assert_equal("0123".b, wrapper.snapshot)
      assert_equal(0, views(copy.instance_variable_get(:@buffer)))
      assert_equal(0, views(wrapper.instance_variable_get(:@buffer)))
    end

    def views(buffer)
      buffer.instance_variable_get(:@dexpace_views).length
    end
  end

  # HTTP-41/BODY-16: the finally-style close on both readers.
  class FinallyTest < DexpaceTestCase
    include Readers

    test "body_bytes returns BINARY and decodes nothing" do
      subject = response(response_body("héllo", media_type: media("text/plain; charset=utf-8")))
      bytes = subject.body_bytes

      assert_equal(::Encoding::BINARY, bytes.encoding)
      assert_equal("héllo".b, bytes)
    end

    test "body_string closes the body" do
      body = response_body("héllo")
      response(body).body_string

      assert_predicate(body, :closed?)
    end

    test "body_bytes closes the body" do
      body = response_body("héllo")
      response(body).body_bytes

      assert_predicate(body, :closed?)
    end

    test "body_string closes the body even when the read fails" do
      body = response_body("héllo")
      body.source.close
      subject = response(body)

      assert_raises(Dexpace::ClosedError) { subject.body_string }
      assert_predicate(body, :closed?)
    end

    test "body_bytes closes the body even when the read fails" do
      body = response_body("héllo")
      body.source.close
      subject = response(body)

      assert_raises(Dexpace::ClosedError) { subject.body_bytes }
      assert_predicate(body, :closed?)
    end

    test "body_bytes on an exhausted body returns an empty BINARY String rather than nil" do
      body = response_body("")
      bytes = response(body).body_bytes

      assert_equal("".b, bytes)
      assert_equal(::Encoding::BINARY, bytes.encoding)
    end

    test "body_string on an empty body returns an empty String in the resolved charset" do
      decoded = response(response_body("", media_type: media("text/plain; charset=utf-8")))
        .body_string

      assert_equal("", decoded)
      assert_equal(::Encoding::UTF_8, decoded.encoding)
    end

    # The handle's close and the body's close are two ensures, not one: a handle whose close
    # raises still leaves the body closed, and the failure still propagates.
    test "body_bytes closes the body even when the handle's own close raises" do
      body = FakeResponseBody.new(RaisingHandle.new("héllo"))

      assert_raises(::IOError) { response(body).body_bytes }
      assert_equal(1, body.closes)
    end

    # A #read-and-#close-shaped handle whose close raises; nothing under Dexpace::IO does that.
    class RaisingHandle
      def initialize(content)
        @content = content.b
      end

      def read = @content

      def close
        raise ::IOError, "the handle's close failed"
      end
    end
  end
end
