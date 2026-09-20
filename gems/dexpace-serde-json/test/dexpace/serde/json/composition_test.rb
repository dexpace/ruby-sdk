# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/serde/json"
require "stringio"

# SEAM-26, SEAM-27, SERDE-28, RECOV-15, HTTP-52/BODY-30 -- composed, not re-satisfied. Every clause
# below has an owning unit test elsewhere; what has no home anywhere is the SEAM between them, and
# Dexpace::Operation (phase 2) is composed with the pipeline and the codec by no phase before this
# one. The socket twin of this slice is phase 8a's, over dexpace-transport-net_http and the
# conformance gem's WireServer, and it spells the contract this lane fixes:
# `StatusAwareHandler.build(serde: Dexpace::Serde::JSON::Codec.default, witness: Pet)` handed to
# `TypedResponse.new(response:, handler:).value`. This one runs `Pipeline.standard` -- the preset a
# generated SDK gets, its three pillars included -- over an in-memory transport (roadmap
# cross-cutting constraint 4: phases 1 through 7 test against an in-memory fake transport): a
# three-positional lambda, which is what Dexpace::Transport.conforms? accepts, recording every
# request it is handed. Core's FakeTransport lives in core's test tree, which another gem's suite
# does not reach into (styleguide 12.6). Split under Metrics/ClassLength: the read side, then the
# write side.
class DexpaceSerdeJSONCompositionTest < DexpaceTestCase
  CODEC = Dexpace::Serde::JSON

  # The DTO a generated SDK would emit for a GET.
  class Pet
    attr_reader :id, :name

    def self.dexpace_load(parsed, ctx)
      h = ctx.object!(parsed)
      new(id: ctx.integer!(h["id"], key: "id"), name: ctx.string!(h["name"], key: "name"))
    end

    def initialize(id:, name:)
      @id = id
      @name = name
    end
  end

  # The PATCH body: one plain field and one tri-state field.
  class PetPatch
    def initialize(name:, nick:)
      @name = name
      @nick = nick
    end

    # SERDE-15: the Absent key is dropped by core's Native walk (P7-9), not by this method.
    def dexpace_dump = { "name" => @name, "nick" => @nick }
  end

  # The error schema a generated SDK's factory decodes the 4xx body into.
  class ErrorWitness
    def self.dexpace_load(parsed, ctx) = ctx.string!(ctx.object!(parsed)["error"], key: "error")
  end

  # The in-memory transport: answers the scripted response, records what it was handed.
  class RecordingTransport
    attr_reader :calls

    def initialize(response)
      @response = response
      @calls = []
    end

    def to_proc = ->(request, options, cancellation) { call(request, options, cancellation) }

    def call(request, options, cancellation)
      @calls << [request, options, cancellation]
      @response
    end
  end

  # The operation, responses, pipeline and typed wrapper the nested cases share.
  module Fixtures
    def show_operation
      Dexpace::Operation.build(method: "GET", template: "/pets/{id}",
                               projections: { id: [:path, "id"] },)
    end

    def json_response(status:, body:, headers: nil)
      buffer = Dexpace::IO::Buffer.new
      buffer.write(body.b)
      builder = Dexpace::Response.builder
      builder.request = Dexpace::Request.build(method: "GET", url: "https://host/v1/pets/0",
                                               headers: Dexpace::Headers::EMPTY,)
      builder.protocol = Dexpace::Protocol::HTTP_1_1
      builder.status = status
      builder.headers = headers unless headers.nil?
      builder.body = Dexpace::Body.buffer(buffer, media_type: Dexpace::MediaType.parse("application/json"))
      builder.build
    end

    def pipeline(transport) = Dexpace::Pipeline.standard(transport.to_proc)

    def pet_json(id = 7, name = "Ré") = "{\"id\":#{id},\"name\":\"#{name}\"}"

    def typed(response, witness: Pet, factory: nil)
      kwargs = { serde: CODEC::Codec.default, witness: witness }
      kwargs[:factory] = factory unless factory.nil?
      Dexpace::TypedResponse.new(response: response,
                                 handler: Dexpace::Serde::StatusAwareHandler.build(**kwargs),)
    end

    def drain(body)
      sink = StringIO.new(+"".b)
      body.write_to(sink)
      sink.string.dup.force_encoding(::Encoding::UTF_8)
    end
  end

  # The GET side: SEAM-26/SEAM-27's composition and SERDE-28's 2xx and 4xx branches.
  class ReadTest < DexpaceTestCase
    include Fixtures

    # SEAM-26 + SEAM-27 + SERDE-28's 2xx branch: descriptor -> request -> pipeline -> typed value.
    test "a 200 walks operation, standard pipeline and codec and decodes to the witness's type" do
      transport = RecordingTransport.new(json_response(status: 200, body: pet_json))
      request = show_operation.build_request(base_url: "https://host/v1", inputs: { id: 7 })

      pet = typed(pipeline(transport).call(request)).value

      assert_equal(1, transport.calls.size)
      assert_equal("https://host/v1/pets/7", transport.calls.first.first.url.to_s)
      assert_equal(Dexpace::Method::GET, transport.calls.first.first.method)
      assert_instance_of(Pet, pet)
      assert_equal(7, pet.id)
      assert_equal("Ré", pet.name)
    end

    # SERDE-28's 4xx/5xx branch through RECOV-15's mapped error and HTTP-52/BODY-30's bounded copy.
    # "so the error body is readable AFTER the live response closes" -- and BODY-30's own words are
    # "decode it, then snapshot it", which is why BufferBody#source hands out a fresh peek view per
    # call (P3-23). Two reads, both after the walk is over.
    test "a 404 raises the factory-built error carrying status, headers and a re-readable body" do
      body = "{\"error\":\"no such pet\"}"
      headers = Dexpace::Headers.inbound_builder.add("x-request-id", "abc123").build
      transport = RecordingTransport.new(json_response(status: 404, body: body, headers: headers))
      request = show_operation.build_request(base_url: "https://host/v1", inputs: { id: 7 })
      response = pipeline(transport).call(request)

      error = assert_raises(Dexpace::ProtocolError) { typed(response).value }

      assert_equal(404, error.status.code)
      assert_equal(["abc123"], error.response.headers["x-request-id"])
      assert_equal(body, error.response.body_string)
      assert_equal(body, error.response.body_string, "BODY-30: readable repeatably after the close")
    end

    # RECOV-15 + SERDE-28's "the MAPPED HTTP-error exception": a generated SDK substitutes its own
    # typed error through the same factory: keyword ErrorMappingStep already uses, and it decodes
    # the buffered error body with its own witness -- the hook an OpenAPI generator needs for a
    # modelled error schema.
    test "the factory keyword lets a generated SDK decode the error body into its own type" do
      api_error = Class.new(::StandardError) { attr_accessor :detail }
      factory = lambda do |response|
        e = api_error.new("HTTP #{response.status.code}")
        e.detail = CODEC.default.load(response.body.source, ErrorWitness)
        e
      end
      transport = RecordingTransport.new(json_response(status: 404, body: "{\"error\":\"gone\"}"))
      request = show_operation.build_request(base_url: "https://host/v1", inputs: { id: 7 })

      error = assert_raises(api_error) do
        typed(pipeline(transport).call(request), factory: factory).value
      end

      assert_equal("gone", error.detail)
      assert_equal("HTTP 404", error.message)
    end

    # SERDE-27's zero-byte clause through the REAL codec: the handler's eof? screen (P7-67) is what
    # names the target, because the parser's own end-of-input error ("unexpected end of input" on
    # json 2.19.9 and 3.0.2, "unexpected token at ''" on 2.7.2 and 2.9.1) names nothing and differs
    # across versions. With the screen gone an empty 200 reads "malformed JSON: …" and no Pet
    # (review round 1, R1-1); the composed path is where a generated SDK meets an empty 200.
    test "an empty 200 raises the handler's target-naming error, never the parser's" do
      transport = RecordingTransport.new(json_response(status: 200, body: ""))
      request = show_operation.build_request(base_url: "https://host/v1", inputs: { id: 7 })

      error = assert_raises(Dexpace::Serde::DeserializationError) do
        typed(pipeline(transport).call(request)).value
      end

      assert_match(/no body to decode into DexpaceSerdeJSONCompositionTest::Pet:/, error.message)
      refute_match(/malformed JSON/, error.message)
    end

    # SEAM-27: "a path value containing a slash is encoded, not split into segments" -- phase 2's
    # own words, asserted here THROUGH the composed path because that is where a generator meets it.
    test "a path parameter containing a slash is one segment on the wire" do
      transport = RecordingTransport.new(json_response(status: 200, body: pet_json(1, "x")))
      request = show_operation.build_request(base_url: "https://host/v1", inputs: { id: "a/b" })

      typed(pipeline(transport).call(request)).value

      sent = transport.calls.first.first

      assert_equal("https://host/v1/pets/a%2Fb", sent.url.to_s)
      assert_equal(4, sent.url.path.split("/").length, "one segment, not two")
    end
  end

  # The write side and the third branch: SERDE-2/SERDE-15/SERDE-19 on a PATCH, and a 304.
  class WriteTest < DexpaceTestCase
    include Fixtures

    # SERDE-15/SERDE-19 through the composed path: SEAM-26's "the body is carried, not encoded"
    # means the OPERATION carries a Dexpace::Body and Body.serialized (SERDE-2) is what encodes it,
    # so the Absent key is dropped by core's Native walk (P7-9) on the way to the wire and the Null
    # one is not, and the Content-Type is the codec's declared media type.
    test "a Tristate::ABSENT field is omitted from the PATCH body and NULL is not" do
      t = Dexpace::Serde::Tristate
      patch = Dexpace::Operation.build(method: "PATCH", template: "/pets/{id}",
                                       projections: { id: [:path, "id"], body: [:body, "body"] },)
      transport = RecordingTransport.new(json_response(status: 200, body: pet_json))
      absent = Dexpace::Body.serialized(PetPatch.new(name: "Ré", nick: t::ABSENT),
                                        serde: CODEC.default,)

      request = patch.build_request(base_url: "https://host/v1", inputs: { id: 7, body: absent })
      typed(pipeline(transport).call(request)).value

      sent = transport.calls.first.first

      assert_equal(Dexpace::Method::PATCH, sent.method)
      assert_equal("{\"name\":\"Ré\"}", drain(sent.body))
      # SERDE-2's default Content-Type travels as the body's media type; the header itself is the
      # transport's to stamp on the wire when the caller set none (TRANSPORT-10, phase 8).
      assert_equal(Dexpace::MediaType.parse("application/json"), sent.body.media_type)
      refute_includes(sent.headers, "content-type", "the model stamps no header; a transport does")

      null = Dexpace::Body.serialized(PetPatch.new(name: "Ré", nick: t::NULL),
                                      serde: CODEC.default,)

      assert_equal("{\"name\":\"Ré\",\"nick\":null}", drain(null))
    end

    # The 304 branch end to end: the standard pipeline does not follow a 304 (REDIR-2) and the
    # handler closes it and raises leading with the code, the raw ETag in the message.
    test "an unfollowed 304 reaches the handler's third branch through the standard pipeline" do
      headers = Dexpace::Headers.inbound_builder.add("etag", "\"v1\"").build
      transport = RecordingTransport.new(json_response(status: 304, body: "", headers: headers))
      request = show_operation.build_request(base_url: "https://host/v1", inputs: { id: 7 })

      error = assert_raises(Dexpace::Serde::DeserializationError) do
        typed(pipeline(transport).call(request)).value
      end

      assert_match(/\A304\b/, error.message)
      assert_match(/"v1"/, error.message)
    end
  end
end
