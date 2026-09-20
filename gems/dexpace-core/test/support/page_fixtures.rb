# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "fake_body"
require_relative "fake_response_body"
require_relative "scripted_transport"
require_relative "scripted_async_transport"

# The requests, responses, strategies and engines every phase-7c pagination suite is written
# against, in the RecoveryFixtures / RedirectFixtures shape. No Response double is written
# anywhere in phase 7c: every response here is a REAL Dexpace::Response built through
# Response.builder over phase 3b's FakeResponseBody (an un-latched #closes counter that raises
# from #close on demand -- the un-latched count is exactly what proves the Page's own latch) or
# phase 4b's RecordingBody, so `response.body.closes` says whether and how often a page's
# response was closed.
#
# The page sequence a test wants -- `[[1, 2], [3]]` -- is scripted through ScriptedStrategy, a
# stateless strategy that reads the page INDEX off the executed request's `p` query parameter
# and derives the next request by splicing `p=index+1`; the transport script it is paired with
# is one callable per page that builds the response around the request the engine actually sent,
# so `response.request` is the executed request the strategies and PAGE-17 read. A test that
# wants to observe or break a page's close hands the fixture its own bodies (`bodies:`), one per
# page; a test that needs the transport reads it back off the engine.
module PageFixtures
  # A stateless strategy over a frozen page script: page `index` yields `pages[index]` and the
  # next request carries `p=index+1`, until the last page, which is terminal.
  class ScriptedStrategy
    def initialize(pages)
      @pages = pages.map { |items| items.dup.freeze }.freeze
      freeze
    end

    def parse(response, template)
      index = (Dexpace::Page::QueryRewriter.get(response.request.url.query, "p") || "0").to_i
      items = @pages.fetch(index) { [] }
      return Dexpace::Page::Info.terminal(items: items) if index + 1 >= @pages.size

      url = Dexpace::Page::QueryRewriter.rewrite_url(template.url, "p", (index + 1).to_s)
      Dexpace::Page::Info.build(items: items, next_request: template.with(url: url))
    end
  end

  # A strategy that always answers the same next request: PAGE-9's "server echoing the same
  # cursor forever".
  class EndlessStrategy
    def parse(_response, template)
      Dexpace::Page::Info.build(items: [1], next_request: template)
    end
  end

  # A strategy whose #parse raises, for PAGE-13's parse-failure paths.
  class RaisingStrategy
    def initialize(error) = @error = error

    def parse(_response, _template)
      raise @error
    end
  end

  def fake_request(url: "https://x/i", method: "GET", headers: {}, body: nil)
    builder = Dexpace::Headers.builder
    headers.each { |name, value| builder.add(name, value) }
    Dexpace::Request.build(method: method, url: url, headers: builder.build, body: body)
  end

  def fake_body = FakeBody.new("payload", replayable: true)

  # A closable response body whose #close raises `close_error` when one is given.
  def fake_response_body(close_error: nil)
    FakeResponseBody.new(Dexpace::IO::BufferedSource.of_bytes("".b), close_error: close_error)
  end

  # A REAL response over a closable body; `headers:` is added through the inbound builder.
  def page_response(request: fake_request, status: 200, headers: {}, body: nil, close_error: nil)
    builder = Dexpace::Response.builder
    builder.request = request
    builder.protocol = Dexpace::Protocol::HTTP_1_1
    builder.status = status
    builder.headers = inbound_headers(headers)
    builder.body = body || fake_response_body(close_error: close_error)
    builder.build
  end

  def inbound_headers(headers)
    inbound = Dexpace::Headers.inbound_builder
    headers.each { |name, values| Array(values).each { |value| inbound.add(name, value) } }
    inbound.build
  end

  def closes_of(response) = response.body.closes

  # One transport script entry per page: a callable that builds the response around the request
  # the engine actually sent, over the body at that index (or a fresh one). `sequences` repeats
  # the script for a test that walks the same engine more than once (PAGE-8).
  def page_script(count, bodies: nil, sequences: 1)
    Array.new(count * sequences) do |index|
      lambda do |request, _options, _cancellation|
        page_response(request: request, body: bodies&.fetch(index % count))
      end
    end
  end

  def scripted_transport(pages, bodies: nil, sequences: 1)
    ScriptedTransport.new(page_script(pages.size, bodies: bodies, sequences: sequences))
  end

  # The strategy-based sync engine over a scripted page sequence.
  def paginator_over(pages, transport: nil, bodies: nil, strategy: nil, sequences: 1, **keywords)
    Dexpace::Page::Paginator.build(
      transport: transport || scripted_transport(pages, bodies: bodies, sequences: sequences),
      template: keywords.delete(:template) || fake_request,
      strategy: strategy || ScriptedStrategy.new(pages),
      **keywords,
    )
  end

  # The async engine over the same scripted sequence; `deferred: true` holds every future for
  # `transport.settle_next!`.
  def async_paginator_over(pages, transport: nil, bodies: nil, strategy: nil, deferred: false,
                           **keywords)
    transport ||= ScriptedAsyncTransport.new(page_script(pages.size, bodies: bodies),
                                             settle_later: deferred,)
    Dexpace::Page::AsyncPaginator.build(
      transport: transport,
      template: keywords.delete(:template) || fake_request,
      strategy: strategy || ScriptedStrategy.new(pages),
      **keywords,
    )
  end

  # A Walk over a paginator's drive, the private objects reached the way 4c's cursor_test reaches
  # its private cursor.
  def walk_over(paginator)
    walk = Dexpace::Page.const_get(:Walk)
    drive = Dexpace::Page::Paginator.const_get(:Drive)
    walk.new(drive.new(paginator), cap: paginator.cap)
  end

  def raising_strategy(error) = RaisingStrategy.new(error)

  # A page over a fresh response, for the fetcher front-end's suites.
  def page_with(items: [], next_link: nil, continuation_token: nil, body: nil)
    Dexpace::Page.build(response: page_response(body: body), items: items, next_link: next_link,
                        continuation_token: continuation_token,)
  end
end
