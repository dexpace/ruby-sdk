# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/redirect_fixtures"
require_relative "../../support/credential_probe"
require_relative "../../support/forking_probe"
require_relative "../../support/state_probe"
require_relative "../../support/spy_cursor"
require_relative "../../support/recording_sink"

# Exercises: REDIR-1 through REDIR-24, REDIR-26, REDIR-28; PIPE-15, PIPE-40 (P4-39), BODY-1,
# HTTP-13, XCUT-19 -- the synchronous redirect pillar step, driven through a real pipeline (only
# the driver makes a forkable cursor) over a scripted transport whose every reply carries a
# close-counting body. Split under Metrics/ClassLength: construction and options; the decision
# skeleton; the credential hygiene and the marker (the correctness-sensitive core); Location
# resolution and the userinfo strip; the downgrade and the target screen; body lifecycle,
# replayability and the 303 rebuild; REDIR-28's records; and the fork-for-every-drive contract.
class DexpaceRedirectStepTest < DexpaceTestCase
  Step = Dexpace::Redirect::Step
  Events = Dexpace::Redirect::Events
  Keys = Dexpace::Redirect::Keys
  STAGES = Dexpace::Pipeline::Stages

  # The steps, requests and pipelines the nested cases share.
  module Fixtures
    include RedirectFixtures

    def logging_step(sink, **)
      redirect_step(logger: Dexpace::Instrumentation::Logger.build(sink: sink), **)
    end

    def event_names(sink)
      sink.payloads.map { |payload| payload[Dexpace::Instrumentation::Keys::EVENT] }
    end

    def payload_for(sink, name)
      sink.payloads.find { |payload| payload[Dexpace::Instrumentation::Keys::EVENT] == name }
    end

    def redirect_to(url, status = 302) = response_with(status, location: url)

    def ok = response_with(200)

    # A 302 per location, nil for a terminal 200.
    def chain(*locations)
      locations.map { |location| location.nil? ? ok : redirect_to(location) }
    end

    def with_token(url = "https://a.example/x")
      seed_request(url, headers: { "Authorization" => "Bearer caller-token" })
    end
  end

  # Task 8: REDIR-3, REDIR-4, REDIR-17, REDIR-26 and the construction pattern.
  class ConstructionTest < DexpaceTestCase
    include Fixtures

    test "installs at Stages::REDIRECT, frozen, built through .build with .new private" do
      step = redirect_step

      assert_equal(STAGES::REDIRECT, step.stage)
      assert_predicate(step, :frozen?)
      assert_raises(NoMethodError) { Step.new }
    end

    test "REDIR-3 / REDIR-4: the default allowed set is exactly {GET, HEAD}, frozen" do
      assert_equal(Set[Dexpace::Method::GET, Dexpace::Method::HEAD], Step::DEFAULT_ALLOWED_METHODS)
      assert_predicate(Step::DEFAULT_ALLOWED_METHODS, :frozen?)
      assert_equal(3, Step::DEFAULT_MAX_HOPS)
    end

    test "REDIR-3: the default is NOT Method::IDEMPOTENT -- OPTIONS, PUT and DELETE are not " \
         "followed by default, GET and HEAD are" do
      %w[OPTIONS PUT DELETE POST PATCH].each do |method|
        response, transport = follow(redirect_step, [redirect_to("https://a.example/y", 301)],
                                     request: seed_request(method: method),)

        assert_equal(301, response.status.code, method)
        assert_equal(1, transport.calls.size, method)
      end
      %w[GET HEAD].each do |method|
        response, = follow(redirect_step, [redirect_to("https://a.example/y", 301), ok],
                           request: seed_request(method: method),)

        assert_equal(200, response.status.code, method)
      end
    end

    test "REDIR-26: a caller's collection is copied at build -- a later mutation changes nothing" do
      methods = ["GET"]
      step = redirect_step(allowed_methods: methods)
      methods << "POST"
      methods.clear

      response, = follow(step,
                         [response_with(301, location: "https://a.example/y"), ok],)

      assert_equal(200, response.status.code) # GET still followed after the clear
      response, transport = follow(step, [response_with(301, location: "https://a.example/y")],
                                   request: seed_request(method: "POST"),)

      assert_equal(301, response.status.code) # POST still refused after the push
      assert_equal(1, transport.calls.size)
    end

    test "REDIR-26: Strings, Symbols and Methods are all accepted; an unknown token is refused" do
      step = redirect_step(allowed_methods: ["post", :Put, Dexpace::Method::GET])
      response, = follow(step, [redirect_to("https://a.example/y", 307), ok],
                         request: seed_request(method: "PUT"),)

      assert_equal(200, response.status.code)
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(allowed_methods: ["G ET"]) }
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(allowed_methods: nil) }
    end

    test "REDIR-17: max_hops must be a non-negative Integer; 0 is accepted" do
      redirect_step(max_hops: 0)
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(max_hops: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(max_hops: 1.5) }
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(max_hops: nil) }
    end

    test "the two flags are Booleans, the predicate is callable with one argument, the logger " \
         "is a Logger" do
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(follow303: "yes") }
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(allow_scheme_downgrade: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(predicate: ->(_a, _b) { true }) }
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(predicate: :follow) }
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(logger: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { redirect_step(logger: RecordingSink.new) }
      always = ->(_snapshot) { true }
      redirect_step(predicate: always, follow303: true, allow_scheme_downgrade: true)
    end
  end

  # Task 9, the built-in route: REDIR-1, REDIR-2, REDIR-16, REDIR-17, REDIR-19.
  class DecisionTest < DexpaceTestCase
    include Fixtures

    test "REDIR-1 / REDIR-2: a non-3xx and a non-recognized 3xx pass through, once, open" do
      [200, 204, 300, 304, 305, 400, 404, 500, 503].each do |code|
        response, transport = follow(redirect_step, [response_with(code, location: "https://a.example/y")])

        assert_equal(code, response.status.code)
        assert_equal(1, transport.calls.size, code)
        assert_equal(0, closes_of(response), code) # REDIR-22c
      end
    end

    test "REDIR-19: a 302 with no Location, or an empty one, is returned unfollowed and open" do
      [nil, ""].each do |location|
        response, transport = follow(redirect_step, [response_with(302, location: location)])

        assert_equal(302, response.status.code)
        assert_equal(1, transport.calls.size)
        assert_equal(0, closes_of(response))
      end
    end

    test "REDIR-16: a loop back to the seed URI is detected; the current response returns OPEN" do
      loop_back = redirect_to("https://a.example/x")
      response, transport = follow(redirect_step, [redirect_to("https://a.example/y"), loop_back])

      assert_same(loop_back, response)
      assert_equal(2, transport.calls.size)
      assert_equal(0, closes_of(response))
    end

    test "REDIR-16: a loop back to an INTERMEDIATE hop is detected too" do
      response, transport = follow(redirect_step(max_hops: 10), [
                                     redirect_to("https://a.example/y"),
                                     redirect_to("https://a.example/z"),
                                     redirect_to("https://a.example/y"),
                                   ],)

      assert_equal(302, response.status.code)
      assert_equal(3, transport.calls.size)
    end

    test "REDIR-17: max_hops caps the loop; the last response is returned as-is, a 3xx included" do
      script = Array.new(5) { |i| redirect_to("https://a.example/#{i + 1}") }
      response, transport = follow(redirect_step(max_hops: 2), script)

      assert_equal(302, response.status.code)
      assert_equal(3, transport.calls.size) # the seed and two followed hops
      assert_equal(0, closes_of(response))
    end

    test "REDIR-17: max_hops 0 disables redirect following entirely" do
      response, transport = follow(redirect_step(max_hops: 0),
                                   [redirect_to("https://a.example/y")],)

      assert_equal(302, response.status.code)
      assert_equal(1, transport.calls.size)
    end
  end

  # Task 9, the predicate route: REDIR-18, REDIR-20, REDIR-21, R9's order and REDIR-22b.
  class PredicateTest < DexpaceTestCase
    include Fixtures

    test "REDIR-20 / REDIR-21: a predicate is consulted on a recognized 3xx with a read-only " \
         "snapshot and fully overrides the default decision" do
      seen = []
      predicate = lambda do |snapshot|
        seen << [snapshot.redirect_count, snapshot.visited_uris.to_a, snapshot.response.status.code]
        false
      end
      response, transport = follow(redirect_step(predicate: predicate),
                                   [redirect_to("https://a.example/y")],)

      assert_equal([[0, ["https://a.example/x"], 302]], seen)
      assert_equal(302, response.status.code) # the default would have followed a GET 302
      assert_equal(1, transport.calls.size)
    end

    test "REDIR-20: a predicate answering true follows what the default would refuse -- a POST " \
         "302, and a revisit -- and the loop still ends at the cap" do
      response, transport = follow(redirect_step(predicate: ->(_s) { true }, max_hops: 4),
                                   Array.new(5) do
                                     redirect_to("https://a.example/x")
                                   end,
                                   request: seed_request(method: "POST", body: replayable_body),)

      assert_equal(302, response.status.code)
      assert_equal(5, transport.calls.size)
    end

    test "REDIR-20: the snapshot's set is a copy -- a predicate mutating it changes nothing" do
      predicate = lambda do |snapshot|
        assert_raises(FrozenError) { snapshot.visited_uris << "https://a.example/y" }
        true
      end
      response, transport = follow(redirect_step(predicate: predicate),
                                   [redirect_to("https://a.example/y"),
                                    redirect_to("https://a.example/z"),
                                    ok,],)

      assert_equal(200, response.status.code)
      assert_equal(%w[https://a.example/x https://a.example/y https://a.example/z],
                   sent_urls(transport),)
    end

    test "REDIR-21: the predicate is NEVER consulted for a non-recognized status" do
      predicate = ->(_snapshot) { raise "must not be called" }
      response, = follow(redirect_step(predicate: predicate), [response_with(404)])

      assert_equal(404, response.status.code)
    end

    test "REDIR-21: a recognized 3xx with no usable Location still allocates the snapshot and " \
         "consults the predicate" do
      seen = []
      predicate = lambda { |snapshot|
        seen << snapshot.redirect_count
        false
      }
      [nil, "", "mailto:a@b", "ht!tp://bad"].each do |location|
        follow(redirect_step(predicate: predicate), [response_with(302, location: location)])
      end

      assert_equal([0, 0, 0, 0], seen)
    end

    test "REDIR-19 + REDIR-20: a predicate that says FOLLOW on a Location-less 3xx still returns " \
         "the response unfollowed, without raising" do
      response, transport = follow(redirect_step(predicate: ->(_s) { true }),
                                   [response_with(302, location: nil)],)

      assert_equal(302, response.status.code)
      assert_equal(1, transport.calls.size)
    end

    test "REDIR-18: an unsupported scheme is returned unfollowed on BOTH decision routes" do
      %w[mailto:someone@example.test ftp://h/z javascript:alert(1)
         data:text/plain,hi].each do |location|
        [nil, ->(_s) { true }].each do |predicate|
          response, transport = follow(redirect_step(predicate: predicate),
                                       [response_with(302, location: location)],)

          assert_equal(302, response.status.code, location)
          assert_equal(1, transport.calls.size, location)
        end
      end
    end

    test "REDIR-17 over REDIR-20 (R9): the cap vetoes a predicate that says FOLLOW, and the " \
         "predicate is still consulted at the cap" do
      seen = []
      predicate = lambda { |snapshot|
        seen << snapshot.redirect_count
        true
      }
      response, transport = follow(redirect_step(max_hops: 1, predicate: predicate),
                                   [redirect_to("https://a.example/y"),
                                    redirect_to("https://a.example/z"),],)

      assert_equal([0, 1], seen) # consulted on the capped hop too, not short-circuited past
      assert_equal(302, response.status.code)
      assert_equal(2, transport.calls.size)
    end

    test "REDIR-22b: a predicate that raises leaves the current response closed behind it" do
      current = redirect_to("https://a.example/y")
      error = assert_raises(RuntimeError) do
        follow(redirect_step(predicate: ->(_s) { raise "predicate boom" }), [current])
      end

      assert_equal("predicate boom", error.message)
      assert_equal(1, closes_of(current))
    end
  end

  # Task 10: REDIR-7, REDIR-8, REDIR-9, REDIR-10, REDIR-11, REDIR-24 -- the correctness-sensitive
  # core, every assertion on EVERY intermediate request and never only on the last.
  class CredentialHygieneTest < DexpaceTestCase
    include Fixtures

    # Hop 1 same-origin, hop 2 cross-origin, then a 200.
    SAME_THEN_CROSS = ["https://a.example/y", "https://b.example/z", nil].freeze

    test "REDIR-7: Authorization is stripped before EVERY re-issue -- same-origin and " \
         "cross-origin -- as seen at the AUTH position and on the wire" do
      probe = CredentialProbe.new
      _, transport = follow(redirect_step, chain(*SAME_THEN_CROSS), request: with_token,
                                                                    downstream: [[probe, STAGES::AUTH]],)

      assert_equal(["Bearer caller-token", nil, nil], probe.decisions.map { |d| d[:authorization] })
      assert_equal(["Bearer probe-token", "Bearer probe-token", nil],
                   sent_requests(transport).map { |sent| sent.headers["Authorization"]&.first },)
    end

    test "REDIR-7: with no AUTH step at all, no re-issue carries the caller's Authorization" do
      _, transport = follow(redirect_step, chain(*SAME_THEN_CROSS), request: with_token)

      sent_requests(transport)[1..].each do |sent|
        refute_includes(sent.headers, "Authorization") # #include? folds; #names is original casing
      end
      assert_equal("Bearer caller-token",
                   sent_requests(transport).first.headers["Authorization"].first,)
    end

    test "REDIR-8 (i): A -> A -> B marks hop 2 cross-origin against the SEED, not the previous " \
         "hop -- which was also A" do
      probe = CredentialProbe.new
      follow(redirect_step, chain("https://a.example/y", "https://b.example/z", nil),
             downstream: [[probe, STAGES::AUTH]],)

      assert_equal([false, false, true], probe.decisions.map { |d| d[:suppressed] })
    end

    test "REDIR-8 (ii): A -> B -> B keeps hop 2 cross-origin -- the seed was A, so a same-origin " \
         "sub-redirect on the foreign host does not re-expose the credential, nor the Cookie" do
      probe = CredentialProbe.new
      headers = { "Authorization" => "Bearer caller-token", "Cookie" => "sid=1" }
      _, transport = follow(redirect_step, chain("https://b.example/y", "https://b.example/z", nil),
                            request: seed_request(headers: headers),
                            downstream: [[probe, STAGES::AUTH]],)

      assert_equal([false, true, true], probe.decisions.map { |d| d[:suppressed] })
      assert_equal(["Bearer probe-token", nil, nil],
                   sent_requests(transport).map { |sent| sent.headers["Authorization"]&.first },)
      # Hop 2 is B -> B: same-origin as the PREVIOUS hop, cross-origin against the SEED. A
      # previous-hop comparison would put the Cookie back on the wire here (REDIR-9).
      assert_equal([["sid=1"], nil, nil],
                   sent_requests(transport).map { |sent| sent.headers["Cookie"] },)
    end

    test "REDIR-8: the host is compared case-insensitively and the port by its effective value" do
      probe = CredentialProbe.new
      follow(redirect_step(max_hops: 5),
             chain("https://A.EXAMPLE/y", "https://a.example:443/z", "HTTPS://a.example/w", nil),
             downstream: [[probe, STAGES::AUTH]],)

      assert_equal([false, false, false, false], probe.decisions.map { |d| d[:suppressed] })
    end

    test "REDIR-8: a different scheme or a different port is a different origin" do
      probe = CredentialProbe.new
      follow(redirect_step(max_hops: 5),
             chain("http://a.example:8080/y", "http://a.example/z", "http://a.example:80/w", nil),
             request: seed_request("http://a.example/x"), downstream: [[probe, STAGES::AUTH]],)

      assert_equal([false, true, false, false], probe.decisions.map { |d| d[:suppressed] })
    end

    test "REDIR-9 / REDIR-10: Cookie and Proxy-Authorization are retained same-origin and " \
         "stripped cross-origin, in one chain" do
      _, transport = follow(redirect_step, chain(*SAME_THEN_CROSS),
                            request: seed_request(headers: { "Cookie" => "session=abc",
                                                             "Proxy-Authorization" => "Basic xyz",
                                                             "Accept" => "*/*", }),)
      sent = sent_requests(transport)

      assert_includes(sent[1].headers, "Cookie") # same-origin: kept
      assert_includes(sent[1].headers, "Proxy-Authorization")
      refute_includes(sent[2].headers, "Cookie") # cross-origin: gone
      refute_includes(sent[2].headers, "Proxy-Authorization")
      assert_includes(sent[2].headers, "Accept") # an unrelated header travels
    end
  end

  # Task 10, the marker: REDIR-11, REDIR-24, and 4c's R11 assertions 4 and 5 against the real step.
  class MarkerTest < DexpaceTestCase
    include Fixtures

    SAME_THEN_CROSS = CredentialHygieneTest::SAME_THEN_CROSS

    test "REDIR-11 / REDIR-24: the marker is written on EVERY drive -- false on the seed's own " \
         "and every same-origin hop, true on every cross-origin hop, never omitted" do
      reader = StateProbe.new(stage_to_read: STAGES::REDIRECT)
      follow(redirect_step, chain(*SAME_THEN_CROSS), downstream: [[reader, STAGES::AUTH]])

      assert_equal([{ cross_origin: false }, { cross_origin: false }, { cross_origin: true }],
                   reader.reads,)
      reader.reads.each { |slot| assert_predicate(slot, :frozen?) }
    end

    test "REDIR-11 (a): the marker is cursor state and no request header -- a forged inbound " \
         "header changes nothing and nothing is added to the wire" do
      probe = CredentialProbe.new
      _, transport = follow(redirect_step, chain("https://a.example/y", nil),
                            request: seed_request(headers: { "X-Dexpace-Cross-Origin" => "true" }),
                            downstream: [[probe, STAGES::AUTH]],)

      assert_equal([false, false], probe.decisions.map { |d| d[:suppressed] })
      on_the_wire = %w[authorization x-dexpace-cross-origin]
      sent_requests(transport).each do |sent|
        names = sent.headers.names.map(&:downcase).sort

        assert_equal(on_the_wire, names) # nothing of the step's on the wire
      end
    end

    test "extends 4c's R11 assertion 4 to the REAL step: an AUTH-position reader sees the " \
         "REDIRECT slot the production step wrote and never RETRY's" do
      retry_writer = ForkingProbe.new(times: 1, state_per_drive: [{ cross_origin: true }])
      redirect_reader = StateProbe.new(stage_to_read: STAGES::REDIRECT)
      retry_reader = StateProbe.new(stage_to_read: STAGES::RETRY)
      follow(redirect_step, chain("https://b.example/z", nil),
             downstream: [[retry_writer, STAGES::RETRY], [redirect_reader, STAGES::AUTH],
                          [retry_reader, STAGES::POST_AUTH],],)

      assert_equal([{ cross_origin: false }, { cross_origin: true }], redirect_reader.reads)
      assert_equal([{ cross_origin: true }, { cross_origin: true }], retry_reader.reads)
    end

    test "R11 assertion 5, against the real step: a second, independent chain on the same " \
         "pipeline never sees the first chain's marker" do
      reader = StateProbe.new(stage_to_read: STAGES::REDIRECT)
      transport = ScriptedTransport.new(chain("https://b.example/z", nil, nil))
      pipeline = redirect_pipeline(redirect_step, transport, [reader, STAGES::AUTH])
      pipeline.call(seed_request("https://a.example/x")) # seed A, hop to B
      pipeline.call(seed_request("https://c.example/x")) # a second call, no redirect

      assert_equal([{ cross_origin: false }, { cross_origin: true }, { cross_origin: false }],
                   reader.reads,)
    end
  end

  # Task 11: REDIR-12, REDIR-13, REDIR-14 -- resolution and the strip, asserted on the RENDERED URL
  # the transport received, never on #userinfo.
  class LocationTest < DexpaceTestCase
    include Fixtures

    test "REDIR-14: a relative Location resolves against the CURRENT hop, not the seed" do
      _, transport = follow(redirect_step, [redirect_to("https://h/v2/a/b"),
                                            redirect_to("c"),
                                            redirect_to("/v3/x"),
                                            ok,],
                            request: seed_request("https://h/v1/x"),)

      assert_equal(%w[https://h/v1/x https://h/v2/a/b https://h/v2/a/c https://h/v3/x],
                   sent_urls(transport),)
    end

    test "REDIR-14: a query-only, a fragment-only and a network-path reference all resolve " \
         "against the CURRENT hop -- the fragment-only one keeps that hop's path and query" do
      _, transport = follow(redirect_step(max_hops: 5),
                            [redirect_to("?page=2"),
                             redirect_to("#only"),
                             redirect_to("//other.example/p"),
                             ok,],
                            request: seed_request("https://h/list?page=1"),)

      assert_equal(%w[https://h/list?page=1 https://h/list?page=2 https://h/list?page=2#only
                      https://other.example/p],
                   sent_urls(transport),)
    end

    test "REDIR-13: a fragment, a percent-encoded fragment, an empty query and an empty fragment " \
         "all reach the transport byte for byte" do
      { "/y#frag" => "https://h/y#frag",
        "/y?q=1#x" => "https://h/y?q=1#x",
        "/y?q=a%23b#c%2Fd" => "https://h/y?q=a%23b#c%2Fd",
        "https://h/y?" => "https://h/y?",
        "https://h/y#" => "https://h/y#", }.each do |location, expected|
        _, transport = follow(redirect_step, chain(location, nil), request: seed_request("https://h/x"))

        assert_equal(expected, sent_urls(transport)[1], location)
      end
    end

    test "REDIR-12 / REDIR-13: userinfo is stripped and the encoded path and query survive " \
         "byte for byte" do
      _, transport = follow(redirect_step, chain("https://user:pass@h/a%2Fb?x=%26y%2Bz", nil),
                            request: seed_request("https://seed.example/x"),)

      assert_equal("https://h/a%2Fb?x=%26y%2Bz", sent_urls(transport)[1])
    end

    test "REDIR-12: a user-only and a password-only userinfo are stripped too" do
      _, transport = follow(redirect_step(max_hops: 5),
                            chain("https://user@h/a", "https://:pass@h/b", nil),)

      assert_equal(%w[https://h/a https://h/b], sent_urls(transport)[1..])
    end

    test "REDIR-13: a bracketed IPv6 host and a non-default port are preserved" do
      _, transport = follow(redirect_step, chain("https://[2001:db8::1]:8443/p%2Fq", nil))

      assert_equal("https://[2001:db8::1]:8443/p%2Fq", sent_urls(transport)[1])
    end

    test "REDIR-13 residue (P5-91): an EXPLICIT default port is elided by URI#to_s upstream, at " \
         "phase 1's re-parse -- the origin is unchanged" do
      probe = CredentialProbe.new
      _, transport = follow(redirect_step, chain("https://a.example:443/y", nil),
                            downstream: [[probe, STAGES::AUTH]],)

      assert_equal("https://a.example/y", sent_urls(transport)[1])
      assert_equal([false, false], probe.decisions.map { |d| d[:suppressed] })
    end
  end

  # Task 11, continued: REDIR-15 and REDIR-18 -- the targets the step refuses to follow. A scheme
  # downgrade raises after the current response is closed (REDIR-22b); an unsupported, host-less
  # or malformed reference returns it unfollowed and open (REDIR-22c).
  class RefusedTargetTest < DexpaceTestCase
    include Fixtures

    test "REDIR-15: an HTTPS -> HTTP downgrade is rejected by default, the current response " \
         "closed before the error propagates (REDIR-22b)" do
      current = redirect_to("http://h/y")
      error = assert_raises(Dexpace::Redirect::SchemeDowngradeError) do
        follow(redirect_step, [current], request: seed_request("https://h/x"))
      end

      assert_includes(error.message, "https://h")
      assert_equal(1, closes_of(current))
    end

    test "REDIR-15: the check is per hop -- http -> https -> http fails on the second transition" do
      second = redirect_to("http://h/z")
      assert_raises(Dexpace::Redirect::SchemeDowngradeError) do
        follow(redirect_step, [redirect_to("https://h/y"), second],
               request: seed_request("http://h/x"),)
      end

      assert_equal(1, closes_of(second))
    end

    test "REDIR-15: the opt-in permits the downgrade and surfaces it observably; credential " \
         "stripping applies regardless" do
      sink = RecordingSink.new
      _, transport = follow(logging_step(sink, allow_scheme_downgrade: true),
                            [redirect_to("http://h/y"), ok],
                            request: seed_request("https://h/x",
                                                  headers: { "Authorization" => "Bearer t",
                                                             "Cookie" => "c", },),)

      assert_equal("http://h/y", sent_urls(transport)[1])
      refute_includes(sent_requests(transport)[1].headers, "Authorization")
      refute_includes(sent_requests(transport)[1].headers, "Cookie") # a scheme change: cross-origin
      assert_includes(event_names(sink), Events::SCHEME_DOWNGRADE_PERMITTED)
      refute_includes(event_names(sink), Events::SCHEME_DOWNGRADE_REJECTED)
    end

    test "REDIR-18: an unsupported scheme and a host-less target return the current response " \
         "unfollowed and OPEN" do
      %w[mailto:someone@example.test ftp://h/z http:foo http:///p https://].each do |location|
        current = response_with(302, location: location)
        response, transport = follow(redirect_step, [current])

        assert_same(current, response, location)
        assert_equal(1, transport.calls.size, location)
        assert_equal(0, closes_of(current), location) # REDIR-22c
      end
    end

    test "REDIR-18: a malformed Location does not throw and returns the current response open" do
      ["ht!tp://user:pass@bad", "https://h/p q", "https://h/<p>", "https://h/pé"].each do |location|
        current = response_with(302, location: location)
        response, transport = follow(redirect_step, [current])

        assert_same(current, response, location)
        assert_equal(1, transport.calls.size, location)
        assert_equal(0, closes_of(current), location)
      end
    end
  end

  # Task 12, the re-issue: REDIR-3, REDIR-4, REDIR-5, REDIR-6 and the 303 rebuild.
  class ReissueTest < DexpaceTestCase
    include Fixtures

    CONTENT_HEADERS = {
      "Content-Type" => "application/json", "Content-Length" => "7", "Content-Language" => "en",
      "Content-MD5" => "deadbeef", "Accept" => "application/json", "Authorization" => "Bearer t",
    }.freeze

    # The same POST carrying the two origin-scoped headers REDIR-9 names beside the rest.
    ORIGIN_SCOPED_HEADERS = CONTENT_HEADERS.merge(
      "Cookie" => "sid=1", "Proxy-Authorization" => "Basic proxy",
    ).freeze

    def post_with_content_headers(body: replayable_body, headers: CONTENT_HEADERS)
      seed_request("https://h/x", method: "POST", body: body, headers: headers)
    end

    # Opted in, a 303 to `location` over the origin-scoped POST; answers the rebuilt GET.
    def rebuilt_get_for(location)
      _, transport = follow(redirect_step(follow303: true),
                            [response_with(303, location: location), ok],
                            request: post_with_content_headers(headers: ORIGIN_SCOPED_HEADERS),)
      sent_requests(transport)[1]
    end

    test "REDIR-5: a 303 is not followed by default" do
      response, transport = follow(redirect_step, [response_with(303, location: "https://h/y")],
                                   request: post_with_content_headers,)

      assert_equal(303, response.status.code)
      assert_equal(1, transport.calls.size)
    end

    test "REDIR-5: opted in, a 303 is re-issued as a GET, body dropped, every Content-* header " \
         "removed by prefix, Authorization stripped, whatever the original method" do
      _, transport = follow(redirect_step(follow303: true),
                            [response_with(303, location: "https://h/y"), ok],
                            request: post_with_content_headers,)
      rebuilt = sent_requests(transport)[1]

      assert_equal("GET", rebuilt.method.token)
      assert_nil(rebuilt.body)
      %w[Content-Type Content-Length Content-Language Content-MD5 Authorization].each do |name|
        refute_includes(rebuilt.headers, name, name)
      end
      assert_includes(rebuilt.headers, "Accept")
    end

    test "REDIR-9 / REDIR-10 on the 303 rebuild: a CROSS-ORIGIN 303 drops Cookie and " \
         "Proxy-Authorization beside Authorization and the Content-* headers; a same-origin " \
         "303 keeps the two origin-scoped headers and drops the rest all the same" do
      foreign = rebuilt_get_for("https://other.example/y")

      assert_equal("GET", foreign.method.token)
      %w[Cookie Proxy-Authorization Authorization Content-Type].each do |name|
        refute_includes(foreign.headers, name, name)
      end
      assert_includes(foreign.headers, "Accept")

      same = rebuilt_get_for("https://h/y")

      assert_equal("GET", same.method.token)
      assert_equal(["sid=1"], same.headers["Cookie"])
      assert_equal(["Basic proxy"], same.headers["Proxy-Authorization"])
      refute_includes(same.headers, "Authorization")
      refute_includes(same.headers, "Content-Type")
    end

    test "REDIR-5 with REDIR-6: a 303 over a NON-replayable body is followed: it drops the body" do
      response, = follow(redirect_step(follow303: true),
                         [response_with(303, location: "https://h/y"), ok],
                         request: post_with_content_headers(body: consumed_body),)

      assert_equal(200, response.status.code)
    end

    test "REDIR-3 / REDIR-4: the ORIGINAL method decides -- POST -> 303 -> GET -> 301 stops at " \
         "the 301 under the default set, because the seed was a POST" do
      response, transport = follow(redirect_step(follow303: true),
                                   [response_with(303, location: "https://h/y"),
                                    response_with(301, location: "https://h/z"),
                                    ok,],
                                   request: seed_request("https://h/x", method: "POST",
                                                                        body: replayable_body,),)

      assert_equal(301, response.status.code)
      assert_equal(2, transport.calls.size)
      assert_equal("GET", sent_requests(transport)[1].method.token)
    end

    test "REDIR-6: a non-replayable body on a followed 307 fails with a clear error naming " \
         "replayability, the current response closed first (REDIR-22b)" do
      current = response_with(307, location: "https://h/y")
      error = assert_raises(Dexpace::NotReplayableError) do
        follow(redirect_step(allowed_methods: ["POST"]), [current],
               request: seed_request("https://h/x", method: "POST", body: consumed_body),)
      end

      assert_match(/replayable/, error.message)
      assert_equal(1, closes_of(current))
    end

    test "REDIR-6: a body-LESS POST 307 is re-issued under an allowed set that admits POST -- " \
         "the gate asks about the body, never RETRY-7's idempotency" do
      response, transport = follow(redirect_step(allowed_methods: ["POST"]),
                                   [response_with(307, location: "https://h/y"),
                                    ok,],
                                   request: seed_request("https://h/x", method: "POST"),)

      assert_equal(200, response.status.code)
      assert_equal("POST", sent_requests(transport)[1].method.token) # REDIR-4: method preserved
    end

    test "REDIR-4 / BODY-1: a replayable body is re-sent as the SAME object with the method kept" do
      body = replayable_body
      _, transport = follow(redirect_step(allowed_methods: ["PUT"]),
                            [response_with(308, location: "https://h/y"), ok],
                            request: seed_request("https://h/x", method: "PUT", body: body),)

      assert_same(body, sent_requests(transport)[1].body)
      assert_equal("PUT", sent_requests(transport)[1].method.token)
    end
  end

  # Task 12, the lifecycle: REDIR-22's three clauses and REDIR-23.
  class LifecycleTest < DexpaceTestCase
    include Fixtures

    test "REDIR-22a: the prior response is closed BEFORE the follow-up reaches the transport, " \
         "not after it returns" do
      hop1 = redirect_to("https://h/y")
      closes_when_next_arrived = nil
      next_reply = lambda do |_request, _options, _cancellation|
        closes_when_next_arrived = closes_of(hop1)
        ok
      end
      follow(redirect_step, [hop1, next_reply])

      assert_equal(1, closes_when_next_arrived) # a [:send, :send, :close] ordering reads 0 here
    end

    test "REDIR-22a / REDIR-22c: each superseded intermediate is closed exactly once; the " \
         "returned response stays open" do
      hop1 = redirect_to("https://h/y")
      hop2 = redirect_to("https://h/z")
      final = ok
      result, = follow(redirect_step, [hop1, hop2, final])

      assert_same(final, result)
      assert_equal(1, closes_of(hop1))
      assert_equal(1, closes_of(hop2))
      assert_equal(0, closes_of(final))
    end

    test "REDIR-22b: a close failure on the superseded response rides the raised error's " \
         "suppressed trail rather than masking it" do
      current = redirect_to("http://h/y")
      current.body.instance_variable_set(:@close_error, IOError.new("close failed"))
      error = assert_raises(Dexpace::Redirect::SchemeDowngradeError) do
        follow(redirect_step, [current], request: seed_request("https://h/x"))
      end

      assert_equal(["close failed"], Dexpace.suppressed(error).map(&:message))
    end

    test "REDIR-23: a chain of 5,000 hops is followed iteratively -- flat on the stack, in " \
         "under a few seconds" do
      depths = []
      script = Array.new(5_000) { |i| redirect_to("https://h/#{i + 1}") }
      script << lambda { |_r, _o, _c|
        depths << caller.size
        ok
      }
      probe = lambda { |_r, _o, _c|
        depths << caller.size
        redirect_to("https://h/1")
      }
      script[0] = probe
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response, transport = follow(redirect_step(max_hops: 5_000), script,
                                   request: seed_request("https://h/0"),)

      assert_equal(200, response.status.code)
      assert_equal(5_001, transport.calls.size)
      assert_equal(depths.first, depths.last) # the 5,000th drive sits at the first drive's depth
      assert_operator(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10.0)
    end
  end

  # Task 13: REDIR-28, XCUT-19 -- the records, the redaction and the raw exception.
  class EmissionTest < DexpaceTestCase
    include Fixtures

    test "REDIR-28: a followed hop emits HOP_FOLLOWED at INFO with both URLs redacted, the " \
         "status and the count" do
      sink = RecordingSink.new
      follow(logging_step(sink), chain("https://user:pass@h/y?token=SECRET", nil),
             request: seed_request("https://seed.example/x?sig=SEED"),)
      hop = payload_for(sink, Events::HOP_FOLLOWED)

      refute_nil(hop)
      assert_equal("https://seed.example/x?sig=***", hop[Keys::FROM_URL])
      assert_equal("https://h/y?token=***", hop[Keys::TO_URL]) # the userinfo was stripped before
      assert_equal(302, hop[Dexpace::Instrumentation::Keys::HTTP_RESPONSE_STATUS_CODE])
      assert_equal(0, hop[Keys::REDIRECT_COUNT])
      assert_equal(:info, sink.entries.find { |e| e.payload.equal?(hop) }.severity)
    end

    test "REDIR-28: loop detection emits LOOP_DETECTED at WARNING, redacted" do
      sink = RecordingSink.new
      follow(logging_step(sink), [redirect_to("https://seed.example/x?k=v")],
             request: seed_request("https://seed.example/x?k=v"),)
      payload = payload_for(sink, Events::LOOP_DETECTED)

      refute_nil(payload)
      assert_equal("https://seed.example/x?k=***", payload[Keys::TO_URL])
      assert_equal(:warn, sink.entries.find { |e| e.payload.equal?(payload) }.severity)
    end

    test "REDIR-28: the malformed-Location event logs the RAW string, never through the " \
         "redactor, with the parser's error as the cause" do
      sink = RecordingSink.new
      follow(logging_step(sink), [redirect_to("ht!tp://user:pass@bad")])
      payload = payload_for(sink, Events::LOCATION_MALFORMED)

      refute_nil(payload)
      assert_equal("ht!tp://user:pass@bad", payload[Keys::LOCATION_RAW])
      assert_match(/InvalidURIError/, payload[Dexpace::Instrumentation::Keys::CAUSE])
    end

    test "REDIR-18: an unsupported scheme and a host-less target emit the same event, raw" do
      %w[ftp://user:pw@h/z mailto:someone@example.test http:///p].each do |location|
        sink = RecordingSink.new
        follow(logging_step(sink), [response_with(302, location: location)])

        assert_equal(location, payload_for(sink, Events::LOCATION_MALFORMED)[Keys::LOCATION_RAW])
      end
    end

    test "REDIR-15 / REDIR-28: the rejected downgrade is emitted under its own name before the " \
         "error, and the permitted one under the other" do
      sink = RecordingSink.new
      assert_raises(Dexpace::Redirect::SchemeDowngradeError) do
        follow(logging_step(sink), [redirect_to("http://h/y?t=S")],
               request: seed_request("https://h/x"),)
      end
      rejected = payload_for(sink, Events::SCHEME_DOWNGRADE_REJECTED)

      refute_nil(rejected)
      assert_equal("http://h/y?t=***", rejected[Keys::TO_URL])
      refute_includes(event_names(sink), Events::SCHEME_DOWNGRADE_PERMITTED)
    end

    test "REDIR-28: a raising redactor degrades to the placeholder; the record is still emitted" do
      raising = Object.new.tap { |r| r.define_singleton_method(:url) { |_value| raise "boom" } }
      sink = RecordingSink.new
      logger = Dexpace::Instrumentation::Logger.build(sink: sink, redactor: raising)
      response, = follow(redirect_step(logger: logger),
                         [redirect_to("https://h/y"), ok],)

      assert_equal(200, response.status.code)
      assert_equal(Dexpace::Instrumentation::Redactor::MALFORMED_URL,
                   payload_for(sink, Events::HOP_FOLLOWED)[Keys::TO_URL],)
    end

    test "OBS-20: a raising sink cannot fail the redirect" do
      sink = RecordingSink.new
      sink.define_singleton_method(:info) { |*_args| raise "sink boom" }
      response, transport = follow(logging_step(sink),
                                   [redirect_to("https://h/y"),
                                    ok,],)

      assert_equal(200, response.status.code)
      assert_equal(2, transport.calls.size)
    end

    test "XCUT-19: no credential reaches any record -- not the seed's userinfo or query, not " \
         "the target's, on any of the four events" do
      sink = RecordingSink.new
      follow(logging_step(sink, allow_scheme_downgrade: true, max_hops: 5),
             [redirect_to("https://u1:p1@h/y?k=S1"),
              redirect_to("http://u2:p2@h/z?k=S2"),
              redirect_to("https://u3:p3@seed.example/x?k=S0"),],
             request: seed_request("https://seed.example/x?k=S0"),)

      assert_equal(4, sink.entries.size)
      rendered = sink.payloads.map(&:inspect).join

      %w[u1 p1 u2 p2 u3 p3 S0 S1 S2].each { |secret| refute_includes(rendered, secret) }
    end

    test "under Logger::NULL nothing is emitted and every path still runs" do
      response, transport = follow(redirect_step(allow_scheme_downgrade: true, max_hops: 5),
                                   [redirect_to("https://h/y"),
                                    redirect_to("http://h/z"),
                                    redirect_to("ht!tp://bad"),],)

      assert_equal(302, response.status.code)
      assert_equal(3, transport.calls.size)
    end
  end

  # PIPE-15 / PIPE-40 (P4-39): the fork-for-every-drive contract, on the cursor the step is handed.
  class ForkingTest < DexpaceTestCase
    include Fixtures

    def spied(step)
      spy = nil
      wrapper = lambda do |request, cursor|
        spy = SpyCursor.new(cursor)
        step.call(request, spy)
      end
      [wrapper, -> { spy }]
    end

    test "forks once per drive, the first included, and never calls the handed cursor" do
      wrapper, spy = spied(redirect_step)
      transport = ScriptedTransport.new([redirect_to("https://h/y"),
                                         redirect_to("https://h/z"),
                                         ok,])
      Dexpace::Pipeline.builder(transport: transport).append(wrapper, stage: STAGES::REDIRECT).build
        .call(seed_request("https://h/x"))

      assert_equal(3, spy.call.forks)
      assert_equal(0, spy.call.calls)
    end

    test "a non-redirect response is one fork and no call" do
      wrapper, spy = spied(redirect_step)
      transport = ScriptedTransport.new([ok])
      Dexpace::Pipeline.builder(transport: transport).append(wrapper, stage: STAGES::REDIRECT).build
        .call(seed_request("https://h/x"))

      assert_equal(1, spy.call.forks)
      assert_equal(0, spy.call.calls)
    end
  end
end
