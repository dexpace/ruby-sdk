# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "recovery_fixtures"
require_relative "fake_body"
require_relative "fake_response_body"
require_relative "sequenced_transport"
require_relative "sequenced_async_transport"
require_relative "forking_probe"

# The requests, responses and pipelines every phase-6c step suite is written against, over
# phase 4b's RecoveryFixtures. A 401 here carries its challenge as a real inbound header, and a
# closable one carries a FakeResponseBody so `body.closes` says whether the step closed it --
# Dexpace::Response has no #closed?; Response#close is `body&.close`.
module AuthFixtures
  include RecoveryFixtures

  STAGES = Dexpace::Pipeline::Stages

  def https_request(method: "GET", body: nil, headers: Dexpace::Headers::EMPTY)
    Dexpace::Request.build(method: method, url: "https://api.example.test/v1/pets",
                           headers: headers, body: body,)
  end

  def http_request
    Dexpace::Request.build(method: "GET", url: "http://api.example.test/v1/pets",
                           headers: Dexpace::Headers::EMPTY,)
  end

  def post_request(replayable: true)
    https_request(method: "POST", body: FakeBody.new("payload", replayable: replayable))
  end

  # A response with a closable body, so the suite can read `closes` off it afterwards.
  def closable_response(code, request: https_request, challenge: nil)
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = code
    builder.headers = challenge_headers(challenge)
    builder.body = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("".b))
    builder.build
  end

  def ok = closable_response(200)

  def unauthorized(challenge = nil) = closable_response(401, challenge: challenge)

  def unauthorized_bearer(realm: "api")
    unauthorized("Bearer realm=\"#{realm}\", error=\"invalid_token\"")
  end

  def challenge_headers(challenge)
    return Dexpace::Headers::EMPTY_INBOUND if challenge.nil?

    Array(challenge).reduce(Dexpace::Headers.inbound_builder) do |builder, value|
      builder.add("WWW-Authenticate", value)
    end.build
  end

  # A sync pipeline: an optional REDIRECT-stage probe forking `redirect_state` in front of the
  # AUTH step, over a SequencedTransport. `redirect_state: nil` installs no redirect step at all
  # -- the "no REDIRECT step" case, whose slot reads as the shared frozen empty Hash.
  def auth_pipeline(step, transport, redirect_state: nil)
    builder = Dexpace::Pipeline.builder(transport: transport)
    unless redirect_state.nil?
      builder.append(ForkingProbe.new(times: 1, state_per_drive: [redirect_state]),
                     stage: STAGES::REDIRECT,)
    end
    builder.append(step).build
  end

  def async_auth_pipeline(step, transport, redirect_state: nil)
    builder = Dexpace::Pipeline::Builder.new(transport: transport)
    unless redirect_state.nil?
      builder.append(ForkingProbe.new(times: 1, state_per_drive: [redirect_state]),
                     stage: STAGES::REDIRECT,)
    end
    builder.append(step).build_async
  end

  def closes_of(response) = response.body.closes
end
