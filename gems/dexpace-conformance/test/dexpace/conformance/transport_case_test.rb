# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# What an assertion body receives (8a's R7, R16): a factory-built transport behind the clause-8
# guard, the borrowed pair (clause 4a), the one send primitive #settle (clause 8), the lazily
# started fixture from a replaceable factory (clause 11), a request against that fixture's port,
# and a teardown the runner drives. Two nested classes under Metrics/ClassLength (6c's shape).
module DexpaceConformanceTransportCaseTest
  TransportCase = Dexpace::Conformance::TransportCase
  Scripts = Dexpace::Conformance::Scripts

  # The doubles both classes share.
  module Doubles
    def build_case(build: ->(**_settings) { :built }, borrow: nil)
      TransportCase.new(build: build, borrow: borrow)
    end

    def guarded_subject(&on_call)
      subject = Object.new
      subject.define_singleton_method(:call, &on_call) if on_call
      subject.define_singleton_method(:close) { @closed = true }
      subject.define_singleton_method(:closed?) { @closed ? true : false }
      subject
    end

    def pair_of(transport, probe_answer)
      Dexpace::Conformance::BorrowedPair.build(transport: transport, probe: -> { probe_answer })
    end
  end

  # The transport, the guard and the send primitive.
  class TransportTest < DexpaceTestCase
    include Doubles

    test "#transport calls the build factory with only the settings given, and tracks it" do
      seen = []
      kase = build_case(build: lambda { |**settings|
        seen << settings
        guarded_subject
      })

      kase.transport(timeout: 1.5)
      kase.transport
      kase.transport(logger: :the_logger)

      assert_equal([{ timeout: 1.5 }, {}, { logger: :the_logger }], seen)
    end

    # Suite contract 8's guard: what an assertion receives cannot be #call-ed. The default #settle
    # IS transport.call, so an assertion calling #call directly passes every run 8a performs and
    # fails only once 8c's async driver replaces #settle -- a defect no test could see otherwise.
    test "#transport returns a subject that refuses #call and delegates everything else" do
      subject = guarded_subject { |*| flunk("the guard must not delegate #call") }
      kase = build_case(build: ->(**_) { subject })

      guarded = kase.transport

      error = assert_raises(ArgumentError) { guarded.call(:r, :o, :c) }
      assert_match(/kase\.settle/, error.message)
      assert_match(/clause 8/, error.message)
      refute_predicate(guarded, :closed?)
      guarded.close

      assert_predicate(guarded, :closed?, "every other message delegates")
      assert_respond_to(guarded, :close)
      refute_respond_to(guarded, :no_such_message)
      assert_raises(NoMethodError) { guarded.no_such_message }
    end

    test "#settle unwraps the guard before handing the transport to the driver's primitive" do
      seen = nil
      subject = guarded_subject do |*args|
        seen = args
        :ok
      end
      kase = build_case(build: ->(**_) { subject })

      assert_equal(:ok, kase.settle(kase.transport, :req, :opts, :cancel))
      assert_equal(%i[req opts cancel], seen)
    end

    # Clause 8: the ONE send primitive. Its default is transport.call with RequestOptions::EMPTY
    # and Cancellation.none defaulted; a driver that replaces it is what lets one assertion body
    # drive a sync adapter and an async one whose future must be awaited.
    test "#settle defaults to transport.call with EMPTY options and no cancellation, replaceably" do
      seen = nil
      transport = guarded_subject do |*args|
        seen = args
        :the_response
      end
      default = build_case

      assert_equal(:the_response, default.settle(transport, :req))
      assert_equal([:req, Dexpace::RequestOptions::EMPTY, Dexpace::Cancellation.none], seen)
      assert_same(TransportCase::DEFAULT_SETTLE, default.instance_variable_get(:@settle))

      awaited = TransportCase.new(build: ->(**_) { :t }, settle: ->(_t, _r, _o, _c) { :awaited })

      assert_equal(:awaited, awaited.settle(transport, :req, :opts, :cancel))
    end

    test "#borrowed_transport raises Vacuous when the adapter supplies no borrowing entry point" do
      kase = build_case(borrow: nil)

      error = assert_raises(Dexpace::Conformance::Vacuous) { kase.borrowed_transport }
      assert_match(/TRANSPORT-15/, error.reason)
    end

    # Suite contract 4a: the factory takes the fixture's PORT and returns a BorrowedPair, so no
    # assertion ever names a native client class; the pair's transport comes back guarded too.
    test "#borrowed_transport calls the borrow factory with the wire's port; the pair is guarded" do
      seen = nil
      borrowed = guarded_subject { |*| flunk("guarded") }
      kase = build_case(borrow: lambda do |port|
        seen = port
        pair_of(borrowed, true)
      end)
      kase.wire(script: Scripts.fixed("x"))

      pair = kase.borrowed_transport

      assert_equal(kase.wire.port, seen)
      assert_predicate(pair, :still_usable?)
      assert_raises(ArgumentError) { pair.transport.call(:r, :o, :c) }
      pair.transport.close

      assert_predicate(borrowed, :closed?)
      kase.teardown
    end
  end

  # The fixture, the request builder and the teardown.
  class FixtureTest < DexpaceTestCase
    include Doubles

    test "#wire starts a WireServer lazily and memoizes it across calls in one case" do
      kase = build_case

      first = kase.wire(script: Scripts.fixed("x"))
      second = kase.wire

      assert_same(first, second)
      assert_kind_of(Dexpace::Conformance::WireServer, first)
      kase.teardown
    end

    # Clause 11: the fixture comes from a factory, so 8c can hand in its own HTTP/2 server.
    test "#wire calls the supplied factory instead of starting a WireServer" do
      built = []
      kase = TransportCase.new(build: ->(**_) { :t }, wire: lambda { |script|
        built << script
        :foreign
      },)

      assert_equal(:foreign, kase.wire(script: :the_script))
      assert_equal(:foreign, kase.wire)
      assert_equal([:the_script], built)
    end

    test "#request builds a Dexpace::Request against #wire's own port, defaulting to a GET of /" do
      kase = build_case
      kase.wire(script: Scripts.fixed("x"))

      request = kase.request
      posted = kase.request(path: "/a?b=1", method: "POST",
                            headers: Dexpace::Headers.builder.tap { |b| b.add("X-A", "1") }.build,
                            body: Dexpace::Body.bytes("x".b),)

      assert_equal("GET", request.method.token)
      assert_equal("http://127.0.0.1:#{kase.wire.port}/", Dexpace::URL.external_form(request.url))
      assert_equal("POST", posted.method.token)
      assert_equal("/a?b=1", posted.url.request_uri)
      assert_equal(["1"], posted.headers["X-A"])
      refute_nil(posted.body)
      kase.teardown
    end

    test "#teardown closes every transport it tracked, the borrowed one included, and the wire" do
      closed = []
      built = Object.new
      built.define_singleton_method(:close) { closed << :built }
      borrowed = Object.new
      borrowed.define_singleton_method(:close) { closed << :borrowed }
      kase = build_case(build: ->(**_) { built }, borrow: ->(_port) { pair_of(borrowed, true) })
      kase.transport
      kase.borrowed_transport
      wire = kase.wire

      kase.teardown

      assert_equal(%i[built borrowed], closed)
      assert_raises(Errno::ECONNREFUSED) { ::TCPSocket.new("127.0.0.1", wire.port).close }
    end

    test "#teardown is a no-op for a case that built nothing and started no wire" do
      assert_nil(build_case.teardown)
    end
  end
end
