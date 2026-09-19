# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "fake_body"
require_relative "fake_response_body"
require_relative "scripted_transport"

# The requests, responses and pipelines every phase-6b redirect suite is written against. Every
# response carries a FakeResponseBody, so `response.body.closes` says whether and how often the
# step closed it -- Dexpace::Response has no #closed?, and REDIR-22's three clauses are all
# assertions about which response was closed and which was left open. A scripted reply may be a
# callable (ScriptedTransport calls it with the request, options and cancellation), which is
# how REDIR-22a's ORDER is observed: the next hop's reply reads the prior response's close count
# at the moment the follow-up reaches the transport.
module RedirectFixtures
  STAGES = Dexpace::Pipeline::Stages

  def seed_request(url = "https://a.example/x", method: "GET", headers: {}, body: nil)
    builder = Dexpace::Headers.builder
    headers.each { |name, value| builder.add(name, value) }
    Dexpace::Request.build(method: method, url: url, headers: builder.build, body: body)
  end

  # A response over a closable body; `location:` adds the Location header, nil adds none.
  def response_with(status, location: nil, headers: {}, request: seed_request)
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = status
    builder.headers = inbound_headers(location, headers)
    builder.body = FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("".b))
    builder.build
  end

  def inbound_headers(location, headers)
    inbound = Dexpace::Headers.inbound_builder
    inbound.add("Location", location) unless location.nil?
    headers.each { |name, value| inbound.add(name, value) }
    inbound.build
  end

  def redirect_step(**) = Dexpace::Redirect::Step.build(**)

  # A sync pipeline with the redirect step at REDIRECT and any further (step, stage) pairs.
  def redirect_pipeline(step, transport, *downstream)
    builder = Dexpace::Pipeline.builder(transport: transport)
      .append(step, stage: STAGES::REDIRECT)
    downstream.each { |(other, stage)| builder.append(other, stage: stage) }
    builder.build
  end

  # Drives `request` through the step over a script; answers the response and the transport.
  def follow(step, script, request: seed_request, downstream: [])
    transport = ScriptedTransport.new(script)
    [redirect_pipeline(step, transport, *downstream).call(request), transport]
  end

  def sent_requests(transport) = transport.calls.map(&:first)

  def sent_urls(transport)
    sent_requests(transport).map { |sent| Dexpace::URL.external_form(sent.url) }
  end

  def closes_of(response) = response.body.closes

  def replayable_body = FakeBody.new("payload", replayable: true)
  def consumed_body = FakeBody.new("payload", replayable: false)
end
