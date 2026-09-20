# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fake_codec"
require_relative "../../support/fake_response_body"
require_relative "../../support/recovery_fixtures"
require "dexpace"

# SERDE-28. Its conformance clause names four cases and one of them is a trap: "2xx -> decode; 500
# (AND A NON-CANONICAL 599) -> the mapped exception with the status code and a readable buffered
# error body; 304 -> serde exception naming the status plus one close." 599 is a 5xx and therefore
# the SECOND branch; a reader skimming "non-canonical" will file it under the third.
#
# The response is a REAL Dexpace::Response over 3b's FakeResponseBody, whose #closes counts RAW
# close calls: a second close in the 4xx branch (which Body.buffer_bounded already closed) would
# read 2 here, where a Closeable-latched body would hide it. Split under Metrics/ClassLength: the
# 2xx and 4xx/5xx branches, the third branch, and the construction.
class DexpaceSerdeStatusAwareHandlerTest < DexpaceTestCase
  S = Dexpace::Serde

  # Named, answering both protocol methods: .dexpace_load is what Dexpace::Serde.witness! requires
  # and .call is what phase 2's FakeCodec#load drives (with BINARY bytes, hence the retag).
  class UpcaseWitness
    def self.dexpace_load(parsed, _ctx) = parsed.dup.force_encoding(::Encoding::UTF_8).upcase
    def self.call(text) = dexpace_load(text, nil)
  end

  # The responses and handlers the nested cases share.
  module Fixtures
    include RecoveryFixtures

    def body_of(text)
      FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes(text.b),
                           content_length: text.bytesize,)
    end

    def response_with(text, code: 200, headers: nil)
      builder = Dexpace::Response.builder
      builder.request = build_request
      builder.protocol = Dexpace::Protocol::HTTP_1_1
      builder.status = code
      builder.headers = headers unless headers.nil?
      builder.body = body_of(text)
      builder.build
    end

    def handler(factory: nil)
      kwargs = { serde: FakeCodec.new, witness: UpcaseWitness }
      kwargs[:factory] = factory unless factory.nil?
      S::StatusAwareHandler.build(**kwargs)
    end
  end

  # The first two branches: 2xx decodes, 4xx/5xx raises the mapped error over the buffered body.
  class MappedTest < DexpaceTestCase
    include Fixtures

    test "SERDE-28: a 2xx decodes through the SAME implementation as the plain handler" do
      response = response_with("héllo", code: 200)

      assert_equal("HÉLLO", handler.call(response))
      assert_equal(1, response.body.closes)
      assert_equal("HÉLLO", handler.call(response_with("héllo", code: 201)))
    end

    test "SERDE-28: a 2xx with no body raises the decoding handler's target-naming error" do
      error = assert_raises(Dexpace::Serde::DeserializationError) { handler.call(build_response(204)) }

      assert_match(/UpcaseWitness/, error.message)
    end

    test "SERDE-28: a 4xx/5xx raises the mapped exception and never decodes the error payload" do
      [400, 404, 500, 599].each do |code|
        response = response_with("boom", code: code)

        error = assert_raises(Dexpace::ProtocolError) { handler.call(response) }

        assert_equal(code, error.status.code)
        assert_nil(error.cause, "constructed by the factory, never chained to an in-flight error")
      end
    end

    test "SERDE-28: the error payload never reaches the witness" do
      touched = false
      witness = Class.new do
        define_singleton_method(:dexpace_load) { |_parsed, _ctx| touched = true }
        define_singleton_method(:call) { |_text| touched = true }
      end
      built = S::StatusAwareHandler.build(serde: FakeCodec.new, witness: witness)

      assert_raises(Dexpace::ProtocolError) { built.call(response_with("b", code: 500)) }
      refute(touched)
    end

    # "carrying a bounded, buffered in-memory copy of the error body (so the error body is readable
    # AFTER the live response closes)" -- and BODY-30's own words are "decode it, then snapshot it",
    # which is why BufferBody#source hands out a fresh peek view per call (P3-23).
    test "SERDE-28: the error body is readable twice after the live response is gone" do
      live = response_with("boom", code: 500)
      error = assert_raises(Dexpace::ProtocolError) { handler.call(live) }

      assert_equal(1, live.body.closes, "the live response was released")
      assert_instance_of(Dexpace::BufferBody, error.response.body)
      assert_equal("boom", error.response.body_string)
      assert_equal("boom", error.response.body_string)
      assert_equal(500, error.response.status.code)
    end

    # RECOV-16's buffering already released the original in an ensure, so this branch must NOT
    # close again -- a second close would be a double close of an object Body.buffer_bounded
    # released, and FakeResponseBody's raw counter is what would show it.
    test "the 4xx/5xx branch adds no second close of its own" do
      response = response_with("boom", code: 500)

      assert_raises(Dexpace::ProtocolError) { handler.call(response) }
      assert_equal(1, response.body.closes)
    end

    test "SERDE-28: a 4xx with no body still raises the mapped error over the bodyless response" do
      error = assert_raises(Dexpace::ProtocolError) { handler.call(build_response(404)) }

      assert_equal(404, error.status.code)
      assert_nil(error.response.body)
    end

    test "SERDE-28: the factory keyword substitutes a generated SDK's typed error" do
      typed = Class.new(::StandardError)
      calls = []
      factory = lambda do |response|
        calls << response
        typed.new("status #{response.status.code}")
      end

      error = assert_raises(typed) { handler(factory: factory).call(response_with("b", code: 503)) }

      assert_equal("status 503", error.message)
      assert_equal(1, calls.size)
      assert_instance_of(Dexpace::BufferBody, calls.first.body, "the factory sees the BUFFERED one")
    end

    test "a factory that returns something other than an Exception is a refused caller mistake" do
      assert_raises(Dexpace::InvalidArgumentError) do
        handler(factory: ->(_response) { :not_an_error }).call(response_with("b", code: 500))
      end
    end

    test "TypedResponse takes it: a 4xx raised through #value is memoized as the same object" do
      failing = response_with("boom", code: 500)
      typed = Dexpace::TypedResponse.new(response: failing, handler: handler)
      first = assert_raises(Dexpace::ProtocolError) { typed.value }
      second = assert_raises(Dexpace::ProtocolError) { typed.value }

      assert_same(first, second)
      assert_equal("boom", first.response.body_string)
    end
  end

  # The third branch. Its message MUST lead with the status code and preserve conditional/redirect
  # context -- by COPYING the raw header values, never by parsing them: running a malformed server
  # ETag through HTTP-48's validating helper inside an error path turns a diagnostic into a second
  # failure (the charter's argument about the unbuilt HTTP-48 helper, honoured).
  class UnhandledTest < DexpaceTestCase
    include Fixtures

    test "SERDE-28: a 304 closes and raises a serde exception leading with the code" do
      headers = headers_with("etag", '"abc"').new_builder.add("location", "/x").build
      response = response_with("", code: 304, headers: headers)

      error = assert_raises(Dexpace::Serde::DeserializationError) { handler.call(response) }

      assert_match(/\A304\b/, error.message)
      assert_match(/"abc"/, error.message)
      assert_match(%r{/x}, error.message)
      assert_match(/UpcaseWitness/, error.message)
      assert_equal(1, response.body.closes)
    end

    test "SERDE-28: a malformed ETag reaches the message verbatim, never a second failure" do
      response = response_with("", code: 304, headers: headers_with("etag", 'W/"unterminated'))

      error = assert_raises(Dexpace::Serde::DeserializationError) { handler.call(response) }

      assert_match(%r{W/"unterminated}, error.message)
    end

    test "SERDE-28: a multi-valued Location is carried whole, joined as the header line reads" do
      response = response_with("", code: 304, headers: headers_with("location", "/a", "/b"))

      error = assert_raises(Dexpace::Serde::DeserializationError) { handler.call(response) }

      assert_match(%r{/a, /b}, error.message)
    end

    test "SERDE-28: a 1xx and an unfollowed 3xx with no conditional headers take this branch too" do
      [100, 301, 307].each do |code|
        response = response_with("", code: code)

        error = assert_raises(Dexpace::Serde::DeserializationError) { handler.call(response) }

        assert_match(/\A#{code}\b/, error.message)
        assert_equal(1, response.body.closes)
      end
    end

    # An anonymous witness has no name for DecodeContext.root to carry (P7-70); the message names
    # it in words rather than interpolating nothing (review round 1, R1-4).
    test "SERDE-28: an anonymous witness is named as such in the third branch's message" do
      anonymous = Class.new { def self.dexpace_load(parsed, ctx) = ctx.object!(parsed) }
      built = S::StatusAwareHandler.build(serde: FakeCodec.new, witness: anonymous)

      error = assert_raises(Dexpace::Serde::DeserializationError) do
        built.call(response_with("", code: 304))
      end

      assert_match(/\A304 Not Modified: not decoded into an anonymous witness,/, error.message)
      refute_match(/#<Class/, error.message)
    end

    test "SERDE-28: the branch closes a bodyless response too, and a close failure propagates" do
      assert_raises(Dexpace::Serde::DeserializationError) { handler.call(build_response(304)) }

      body = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("".b),
                                  close_error: ::IOError.new("boom"),)
      failing = build_response(304, body: body)

      assert_raises(::IOError) { handler.call(failing) }
      assert_equal(1, body.closes)
    end
  end

  # The construction pattern, and the arguments refused at build.
  class ConstructionTest < DexpaceTestCase
    include Fixtures

    test "follows the construction pattern: private constructors, frozen, #with through .build" do
      built = handler
      substitute = built.with(factory: ->(r) { ::RuntimeError.new(r.status.code.to_s) })

      refute_respond_to(S::StatusAwareHandler, :new)
      refute_respond_to(S::StatusAwareHandler, :[])
      assert_predicate(built, :frozen?)
      assert_equal("HÉLLO", substitute.call(response_with("héllo")))
      assert_raises(::RuntimeError) { substitute.call(response_with("b", code: 500)) }
    end

    test "a non-witness, a nil serde and a bad factory each fail at construction" do
      assert_raises(Dexpace::InvalidArgumentError) do
        S::StatusAwareHandler.build(serde: FakeCodec.new, witness: 5)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        S::StatusAwareHandler.build(serde: nil, witness: UpcaseWitness)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        S::StatusAwareHandler.build(serde: FakeCodec.new, witness: UpcaseWitness, factory: nil)
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        S::StatusAwareHandler.build(serde: FakeCodec.new, witness: UpcaseWitness,
                                    factory: Object.new,)
      end
    end

    test "anything but a Dexpace::Response is refused" do
      assert_raises(Dexpace::InvalidArgumentError) { handler.call(nil) }
      assert_raises(Dexpace::InvalidArgumentError) { handler.call("200") }
    end
  end
end
