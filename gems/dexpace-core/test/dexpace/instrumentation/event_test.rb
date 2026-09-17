# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/recording_sink"
require_relative "../../support/diagnostic_context"
require_relative "../../support/allocation_delta"
require_relative "../../../lib/dexpace/instrumentation/logger"

# Exercises: OBS-1, OBS-3, OBS-4, OBS-5, OBS-6, OBS-7, OBS-8, OBS-9, OBS-11, OBS-16, OBS-17,
# OBS-18, OBS-39, OBS-40
#
# Every live event here is obtained the only way one can be, from a Logger over a RecordingSink;
# nothing reaches Event.new. The private Render module's contract (OBS-6, OBS-7) is asserted
# here, at its call site, and has no mirror of its own (P2-15, P4-3).
#
# Split into nested classes under Metrics/ClassLength: the inert event, the accumulator, the
# merge and the tag, the rendering, the header-name gate, the two ambient sources.
class DexpaceInstrumentationEventTest < DexpaceTestCase
  include AllocationDelta

  Event = Dexpace::Instrumentation::Event
  Logger = Dexpace::Instrumentation::Logger
  Severity = Dexpace::Instrumentation::Severity
  Keys = Dexpace::Instrumentation::Keys

  # R8. Two properties make this assertion portable, and neither is the file's magic comment:
  # every argument is a Symbol, an Integer or nil, none of which allocates on any Ruby with or
  # without `# frozen_string_literal: true` (a bare "x" literal allocates one object per call in
  # a file that lacks it, which is how the same assertion would fail in dexpace-conformance
  # against a CORRECT implementation); and the measurement is the difference of two loop sizes,
  # asserted exactly 0.0 per call, never an absolute count under a bound. This file carries the
  # magic comment by repository rule; that is NOT this test's precondition, and phase 8a copies
  # this comment with the assertion.
  test "OBS-1: the inert chain allocates nothing per call and returns the singleton" do
    inert = Event::INERT

    assert_predicate(inert, :frozen?)
    assert_in_delta(0.0, allocations_per_call { inert.field(:k, 1).event(:x).cause(nil).emit }, 0.0)
  end

  test "OBS-1: the inert event's builders return self, its emit returns nil, and it is an Event" do
    inert = Event::INERT

    assert_same(inert, inert.field("key", "value"))
    assert_same(inert, inert.event("name"))
    assert_same(inert, inert.cause(::StandardError.new))
    assert_nil(inert.emit)
    assert_kind_of(Event, inert)
    assert_raises(::NameError) { Dexpace::Instrumentation::Event::Inert }
    refute_respond_to(Event, :new)
  end

  test "OBS-1: an inert chain from a disabled logger produces no output at all" do
    sink = RecordingSink.new(info_enabled: false)
    event = Logger.build(sink: sink).event(Severity::INFO)

    assert_same(Event::INERT, event)
    assert_nil(event.field("k", "v").event("x").cause(::IOError.new("io")).emit)
    assert_empty(sink.entries)
  end

  # OBS-3, OBS-8, OBS-39: the accumulator and its one emit.
  class AccumulatorTest < DexpaceTestCase
    Logger = Dexpace::Instrumentation::Logger
    Keys = Dexpace::Instrumentation::Keys
    Severity = Dexpace::Instrumentation::Severity

    def live(sink, severity: Severity::INFO)
      Logger.build(sink: sink).event(severity)
    end

    test "OBS-3: an empty or non-name key is refused with SEAM-29's one message form" do
      event = live(RecordingSink.new)

      ["", :"", nil, 42].each do |key|
        error = assert_raises(Dexpace::InvalidArgumentError, key.inspect) { event.field(key, "v") }
        assert_equal("field key is required", error.message)
      end
    end

    test "OBS-3: a nil value is not dropped; it is emitted as the literal String null" do
      sink = RecordingSink.new
      live(sink).field("nothing", nil).field(:sym, nil).emit

      assert_equal({ "nothing" => "null", "sym" => "null" }, sink.payloads.first)
    end

    test "OBS-8: a second emit on the same instance is a no-op" do
      sink = RecordingSink.new
      event = live(sink).field("k", "v")

      assert_nil(event.emit)
      assert_nil(event.emit)
      assert_equal(1, sink.entries.size)
    end

    # OBS-8's race, deterministic: four threads parked on one queue, released together onto one
    # instance; exactly one output.
    test "OBS-8: the terminal emit is safe to call from any thread and happens once" do
      sink = RecordingSink.new
      event = live(sink).field("k", "v")
      gate = ::Thread::Queue.new
      threads = Array.new(4) do
        ::Thread.new do
          gate.pop
          event.emit
        end
      end
      4.times { gate << true }
      threads.each(&:join)

      assert_equal(1, sink.entries.size)
    end

    test "OBS-8: the sink is called outside the mutex; a sink that re-enters the logger works" do
      sink = RecordingSink.new
      logger = Logger.build(sink: sink)
      reentrant = ::Object.new
      reentrant.define_singleton_method(:to_s) do
        logger.event(Severity::INFO).field("inner", 1).emit
        "outer"
      end
      logger.event(Severity::INFO).field("outer", reentrant).emit

      assert_equal(2, sink.entries.size)
      assert_equal({ "inner" => 1 }, sink.payloads[0])
      assert_equal({ "outer" => "outer" }, sink.payloads[1])
    end

    # The mutex is released BEFORE the sink is called: a sink that logs through the same logger
    # from inside its own write -- a second event, the same mutex -- would otherwise meet
    # Thread::Mutex's non-reentrancy as `ThreadError: deadlock; recursive locking`.
    test "OBS-8: a sink that logs through the same logger inside its write does not deadlock" do
      sink = RecordingSink.new
      logger = Logger.build(sink: sink)
      sink.define_singleton_method(:info) do |message = nil, &block|
        logger.event(Severity::WARNING).field("nested", true).emit unless block.nil?
        super(message, &block)
      end
      logger.event(Severity::INFO).field("outer", 1).emit

      assert_equal(%i[warn info], sink.entries.map(&:severity))
    end

    test "OBS-2, OBS-39: the record reaches the sink through the block form of the method" do
      sink = RecordingSink.new
      live(sink, severity: Severity::WARNING).field("k", 1).emit
      live(sink, severity: Severity::VERBOSE).field("k", 2).emit

      assert_equal(%i[warn debug], sink.entries.map(&:severity))
      assert_nil(sink.entries[0].message, "the block form, not a positional message")
      assert_equal({ "k" => 1 }, sink.entries[0].payload)
    end

    test "OBS-39: the cause is attached under the cause key as SimpleClassName: message" do
      sink = RecordingSink.new
      live(sink).cause(::IOError.new("stream severed")).emit
      live(sink).cause(::IOError.new("x")).cause(nil).emit

      assert_equal("IOError: stream severed", sink.payloads[0][Keys::CAUSE])
      refute(sink.payloads[1].key?(Keys::CAUSE), "a nil cause clears it")
    end

    test "a later field with the same key replaces the earlier and a Symbol key is its name" do
      sink = RecordingSink.new
      live(sink).field("k", 1).field(:k, 2).emit

      assert_equal({ "k" => 2 }, sink.payloads.first)
    end
  end

  # OBS-4, OBS-5, OBS-9, OBS-40: the merge, the tag and the collision diagnostic.
  class MergeTest < DexpaceTestCase
    Logger = Dexpace::Instrumentation::Logger
    Keys = Dexpace::Instrumentation::Keys
    Severity = Dexpace::Instrumentation::Severity
    Diagnostics = Dexpace::Instrumentation::Diagnostics

    test "OBS-4: event(name) writes the tag under the reserved key and an empty name clears it" do
      sink = RecordingSink.new
      logger = Logger.build(sink: sink)
      logger.event(Severity::INFO).event("order_placed").emit
      logger.event(Severity::INFO).event(:symbolic).emit
      logger.event(Severity::INFO).event("temp").event("").emit
      logger.event(Severity::INFO).event("temp").event(nil).emit

      assert_equal("order_placed", sink.payloads[0][Keys::EVENT])
      assert_equal("symbolic", sink.payloads[1][Keys::EVENT])
      refute(sink.payloads[2].key?(Keys::EVENT))
      refute(sink.payloads[3].key?(Keys::EVENT))
    end

    # The chapter's own case: the same key from all three sources with distinct values, the
    # per-event value the single emitted one. A test that supplies two of the three passes under
    # an implementation that gets the third wrong.
    test "OBS-5: per-event wins over global context, both win over folded diagnostic context" do
      sink = RecordingSink.new
      logger = Logger.build(sink: sink, context: { "shared" => "global", "global_only" => "g" },
                            diagnostic_keys: %i[shared trace.id],)
      DiagnosticContext.preserve do
        ::Fiber[:shared] = "diagnostic"
        ::Fiber[:"trace.id"] = "t"
        logger.event(Severity::INFO).field("shared", "event").emit
      end
      payload = sink.payloads.first

      assert_equal("event", payload["shared"])
      assert_equal("g", payload["global_only"])
      assert_equal("t", payload["trace.id"])
      assert_equal(1, payload.keys.count("shared"))
    end

    # OBS-4 names three sources an `event` key can arrive from and requires each suppressed
    # under a tag; OBS-40 requires exactly one of the three -- the per-event field -- to be
    # warned about and the other two to defer silently. Six assertions, not two.
    test "OBS-4, OBS-40: under a tag every ambient event key is suppressed; only a field warns" do
      sink = RecordingSink.new
      logger = Logger.build(sink: sink, context: { "event" => "from_context" },
                            diagnostic_keys: nil,)
      DiagnosticContext.preserve do
        ::Fiber[:event] = "from_diagnostic"
        logger.event(Severity::INFO).event("tag").emit
      end

      assert_equal(1, sink.entries.size, "ambient event keys defer silently")
      assert_equal("tag", sink.payloads[0][Keys::EVENT])

      logger.event(Severity::INFO).event("tag").field(Keys::EVENT, "from_field").emit

      assert_equal(3, sink.entries.size, "one debug diagnostic, one event")
      assert_equal(:debug, sink.entries[1].severity)
      assert_match(/collided/, sink.entries[1].payload)
      assert_equal("tag", sink.payloads[2][Keys::EVENT])
    end

    test "OBS-40: the collision diagnostic fires at most once per logger, never with verbose off" do
      sink = RecordingSink.new(debug_enabled: false)
      logger = Logger.build(sink: sink)
      2.times { logger.event(Severity::INFO).event("tag").field(Keys::EVENT, "x").emit }

      assert_equal(%i[info info], sink.entries.map(&:severity), "gated on the verbose level")

      sink.debug_enabled = true
      3.times { logger.event(Severity::INFO).event("tag").field(Keys::EVENT, "x").emit }

      assert_equal(%i[info info debug info info info], sink.entries.map(&:severity))
      other = Logger.build(sink: sink)
      other.event(Severity::INFO).event("tag").field(Keys::EVENT, "x").emit

      assert_equal(:debug, sink.entries[-2].severity, "a second logger has its own latch")
    end

    test "OBS-4: without a tag a per-event field named event is emitted as an ordinary field" do
      sink = RecordingSink.new
      Logger.build(sink: sink).event(Severity::INFO).field(Keys::EVENT, "plain").emit

      assert_equal("plain", sink.payloads.first[Keys::EVENT])
      assert_equal(1, sink.entries.size, "no diagnostic: nothing collided")
    end

    test "OBS-9: the global context is attached to every event, keyed by String, the same object" do
      sink = RecordingSink.new
      logger = Logger.build(sink: sink, context: { region: "eu", "tier" => 1 })
      3.times { |index| logger.event(Severity::INFO).field("n", index).emit }

      assert_equal(3, sink.entries.size)
      sink.payloads.each do |payload|
        assert_equal("eu", payload["region"])
        assert_equal(1, payload["tier"])
      end
      assert_same(logger.context, logger.context)
    end
  end

  # OBS-6, OBS-7 and the reserved-key table: rendering at the call site of the private Render.
  class RenderingTest < DexpaceTestCase
    Logger = Dexpace::Instrumentation::Logger
    Keys = Dexpace::Instrumentation::Keys
    Redactor = Dexpace::Instrumentation::Redactor
    Severity = Dexpace::Instrumentation::Severity

    def rendered(value)
      sink = RecordingSink.new
      Logger.build(sink: sink).event(Severity::INFO).field("v", value).emit
      sink.payloads.first["v"]
    end

    test "OBS-6: primitives pass through type-preserving; Strings and Symbols render as text" do
      assert_equal(42, rendered(42))
      assert_in_delta(3.5, rendered(3.5))
      assert_equal(Rational(1, 3), rendered(Rational(1, 3)))
      assert_equal(true, rendered(true)) # rubocop:disable Minitest/AssertTruthy -- the value, not truthiness
      assert_equal(false, rendered(false)) # rubocop:disable Minitest/RefuteFalse -- the value, not falsiness
      assert_equal("text", rendered("text"))
      assert_equal("sym", rendered(:sym))
    end

    test "OBS-6: an exception renders as SimpleClassName: message, Class when anonymous" do
      assert_equal("InvalidArgumentError: bad", rendered(Dexpace::InvalidArgumentError.new("bad")))
      assert_equal("Class: anon", rendered(::Class.new(::StandardError).new("anon")))
    end

    test "OBS-6: collections render in a bracketed textual form" do
      assert_equal("[1, \"a\", :b]", rendered([1, "a", :b]))
      hash = rendered({ "a" => 1 })

      # Hash#inspect's spacing changed at 3.4.0 ({"a"=>1} before, {"a" => 1} from 3.4); OBS-6
      # fixes a shape, not a spelling, so the assertion is on the shape.
      assert_operator(hash, :start_with?, "{")
      assert_operator(hash, :end_with?, "}")
      assert_includes(hash, "\"a\"")
      assert_includes(hash, "1")
    end

    # Verified fact 8: three independent ways rendering is hostile, none of which escapes.
    test "OBS-6: a value whose rendering raises becomes [unrenderable ClassName], never a raise" do
      hostile = ::Object.new
      def hostile.to_s = raise("boom")
      # Array#inspect renders its elements with #inspect, not #to_s.
      def hostile.inspect = raise("boom")
      bad_message = ::Class.new(::StandardError) { def message = raise("boom") }.new

      assert_equal("[unrenderable Object]", rendered(hostile))
      assert_equal("[unrenderable Class]", rendered(bad_message))
      assert_equal("[unrenderable BasicObject]", rendered(::BasicObject.new))
      assert_equal("[unrenderable Array]", rendered([hostile]))
    end

    # OBS-7's conformance sentence says "output length equals cap+suffix" and String#length is
    # characters; the cap is a byte figure (P5-29), so the assertion is on bytesize and the
    # divergence is named here rather than resolved silently.
    test "OBS-7: a rendered value over 8 KiB is cut on a byte boundary, scrubbed, and marked" do
      value = rendered("€" * 4000)
      marker = "...[truncated]"

      assert_predicate(value, :valid_encoding?)
      assert_operator(value, :end_with?, marker)
      assert_equal(8190 + marker.bytesize, value.bytesize, "8192 bytes cut the 2731st € in half")
      assert_equal(2730 + marker.length, value.length)
      assert_equal("x" * 8192, rendered("x" * 8192), "exactly the cap is not truncated")
      assert_equal(("x" * 8192) + marker, rendered("x" * 8193), "one over is")
    end

    test "OBS-6: a String in a non-ASCII-compatible encoding is transcoded to UTF-8 first" do
      rendered = rendered("héllo".encode(::Encoding::UTF_16LE))

      assert_equal("héllo", rendered)
      assert_equal(::Encoding::UTF_8, rendered.encoding)
    end

    # The placeholder's own fallback: a class whose .name raises defeats even the class-name
    # derivation, and the rendering still comes back as a String.
    test "OBS-6: a value whose class name itself raises still renders as a placeholder" do
      doubly_hostile = ::Class.new do
        def self.name = raise("no name")
        def to_s = raise("no text")
      end.new

      assert_equal("[unrenderable Object]", rendered(doubly_hostile))
    end

    test "OBS-7: a BINARY value is truncated too, and a numeric primitive is exempt" do
      binary = rendered(("\xFF" * 9000).b)

      assert_equal(::Encoding::BINARY, binary.encoding)
      assert_equal(8192 + "...[truncated]".bytesize, binary.bytesize)
      assert_equal(10**5000, rendered(10**5000))
    end

    test "OBS-39, OBS-11..OBS-17: url.full and the header keys are redacted on the way in" do
      sink = RecordingSink.new
      request = Keys::HTTP_REQUEST_HEADER_PREFIX
      response = Keys::HTTP_RESPONSE_HEADER_PREFIX
      event = Logger.build(sink: sink).event(Severity::INFO)
      event.field(Keys::URL_FULL, "https://user:pass@example.com/api?token=secret&api-version=1")
      event.field("#{request}location", "/cb?code=SECRET")
      event.field("#{response}content-location", "https://h/x#t=1")
      event.field("#{response}content-type", "text/plain?not=a-url")
      event.field("#{response}location", nil)
      event.field("url.other", "https://user:pass@example.com/")
      event.emit
      payload = sink.payloads.first

      assert_equal("https://***:***@example.com/api?token=***&api-version=1",
                   payload[Keys::URL_FULL],)
      assert_equal("/cb?***", payload["#{request}location"])
      assert_equal("https://h/x#t=***", payload["#{response}content-location"])
      assert_equal("text/plain?not=a-url", payload["#{response}content-type"])
      assert_equal("null", payload["#{response}location"], "OBS-3, not the redactor")
      assert_equal("https://user:pass@example.com/", payload["url.other"], "only the reserved keys")
      refute_includes(payload.inspect, "secret")
      refute_includes(payload.inspect, "SECRET")
    end

    test "OBS-39: a malformed url.full is the sentinel, and the logger's own redactor is used" do
      sink = RecordingSink.new
      policy = Dexpace::Instrumentation::RedactionPolicy.build(query_allow_list: %w[token])
      logger = Logger.build(sink: sink, redactor: Redactor.build(policy: policy))
      logger.event(Severity::INFO).field(Keys::URL_FULL, "not a url").emit
      logger.event(Severity::INFO).field(Keys::URL_FULL, "https://h/?token=kept").emit

      assert_equal(Redactor::MALFORMED_URL, sink.payloads[0][Keys::URL_FULL])
      assert_equal("https://h/?token=kept", sink.payloads[1][Keys::URL_FULL])
    end
  end

  # OBS-18 at Event#field (P5-102): the header-name gate is structural, like OBS-39's.
  class HeaderGateTest < DexpaceTestCase
    Logger = Dexpace::Instrumentation::Logger
    Keys = Dexpace::Instrumentation::Keys
    Redactor = Dexpace::Instrumentation::Redactor
    Policy = Dexpace::Instrumentation::RedactionPolicy
    Severity = Dexpace::Instrumentation::Severity

    # P5-102: OBS-18's name gate is keyed by the field NAME like OBS-39's, so a credential
    # header written straight into #field -- by an SDK author, never by the step -- is marked
    # exactly as the step's would be. The round-0 review found this path logging the value.
    test "OBS-18, P5-102: a non-allow-listed header written through #field is REDACTED" do
      sink = RecordingSink.new
      request = Keys::HTTP_REQUEST_HEADER_PREFIX
      response = Keys::HTTP_RESPONSE_HEADER_PREFIX
      event = Logger.build(sink: sink).event(Severity::INFO)
      event.field("#{request}authorization", "Bearer sk-live-1")
      event.field("#{request}Authorization", "Bearer sk-live-2")
      event.field("#{response}set-cookie", "sid=SECRET")
      event.field("#{request}x-api-key", nil)
      event.field("#{request}content-type", "text/plain")
      event.emit
      payload = sink.payloads.first

      assert_equal(Redactor::REDACTED_HEADER, payload["#{request}authorization"])
      assert_equal(Redactor::REDACTED_HEADER, payload["#{request}Authorization"], "folded name")
      assert_equal(Redactor::REDACTED_HEADER, payload["#{response}set-cookie"])
      assert_equal(Redactor::REDACTED_HEADER, payload["#{request}x-api-key"], "nil is not logged")
      assert_equal("text/plain", payload["#{request}content-type"])
      refute_includes(payload.inspect, "sk-live")
      refute_includes(payload.inspect, "SECRET")
    end

    test "OBS-18, P5-102: in omit mode a non-allow-listed header through #field is dropped" do
      sink = RecordingSink.new
      policy = Policy::DEFAULT.with(omit_disallowed_headers: true)
      logger = Logger.build(sink: sink, redactor: Redactor.build(policy: policy))
      event = logger.event(Severity::INFO)
      event.field("#{Keys::HTTP_REQUEST_HEADER_PREFIX}authorization", "Bearer sk-live-1")
      event.field("#{Keys::HTTP_REQUEST_HEADER_PREFIX}accept", "text/html")
      event.emit
      payload = sink.payloads.first

      assert_equal({ "#{Keys::HTTP_REQUEST_HEADER_PREFIX}accept" => "text/html" }, payload)
    end

    # The two gates compose in the order the requirements do: a URL-valued name that a policy
    # has removed from the allow-list is not logged at all, so its URL is never redacted -- the
    # name gate runs first, as the design says of the step, and now of every caller.
    test "OBS-17, OBS-18, P5-102: the name gate runs before the URL-value redactor" do
      sink = RecordingSink.new
      policy = Policy::DEFAULT.with(header_allow_list: %w[accept])
      logger = Logger.build(sink: sink, redactor: Redactor.build(policy: policy))
      key = "#{Keys::HTTP_RESPONSE_HEADER_PREFIX}location"
      logger.event(Severity::INFO).field(key, "https://u:p@h/cb?code=S").emit

      assert_equal(Redactor::REDACTED_HEADER, sink.payloads.first[key])
    end

    # P5-108 (review round 2's R2-2): an Array under a header key is a multi-valued header --
    # what the Emitter hands over for every header, and what a caller may write by hand -- and
    # each value meets the redactor on its own before the ", " join. The round-2 review found
    # the Emitter joining first, so the second value's userinfo sat behind the first value's
    # path; and an Array written by hand took the surgery route on its #inspect form.
    test "OBS-11, OBS-16, OBS-17, P5-108: an Array header value is redacted per value, joined" do
      sink = RecordingSink.new
      request = Keys::HTTP_REQUEST_HEADER_PREFIX
      response = Keys::HTTP_RESPONSE_HEADER_PREFIX
      event = Logger.build(sink: sink).event(Severity::INFO)
      event.field("#{response}location",
                  ["https://user:secret@a/x?code=S", "//user:secret@b/y", "/cb#f"],)
      event.field("#{request}accept", ["text/html", "application/json"])
      event.field("#{request}authorization", ["Bearer sk-live-1", "Bearer sk-live-2"])
      event.field("#{response}etag", ["\"one\""])
      event.field("custom.list", ["https://user:secret@a/x", 1])
      event.emit
      payload = sink.payloads.first

      assert_equal("https://***:***@a/x?code=***, //***:***@b/y, /cb?***",
                   payload["#{response}location"],)
      assert_equal("text/html, application/json", payload["#{request}accept"])
      assert_equal(Redactor::REDACTED_HEADER, payload["#{request}authorization"])
      assert_equal("\"one\"", payload["#{response}etag"])
      # A key the table does not reserve keeps its Array and renders as a collection (OBS-6).
      assert_equal(["https://user:secret@a/x", 1].inspect, payload["custom.list"])
      refute_includes(payload["#{response}location"], "secret")
      refute_includes(payload.inspect, "sk-live")
    end
  end

  # P5-104 (review round 1's R1-2): OBS-39's "the logged url.full MUST always be the redacted
  # URL" and OBS-18's "MUST NOT have its value logged" are stated on the EMITTED record, and
  # OBS-5 names three sources a key can arrive from. The round-1 review found the table running
  # at #field alone, so a reserved key supplied by the logger's global context or by the
  # diagnostic fold reached the sink raw. Both ambient sources now meet the same table.
  class AmbientSourcesTest < DexpaceTestCase
    Logger = Dexpace::Instrumentation::Logger
    Keys = Dexpace::Instrumentation::Keys
    Redactor = Dexpace::Instrumentation::Redactor
    Policy = Dexpace::Instrumentation::RedactionPolicy
    Severity = Dexpace::Instrumentation::Severity

    AUTHORIZATION = "#{Keys::HTTP_REQUEST_HEADER_PREFIX}authorization".freeze
    LOCATION = "#{Keys::HTTP_RESPONSE_HEADER_PREFIX}location".freeze

    test "OBS-39, OBS-18, P5-104: reserved keys in the global context are redacted at build" do
      sink = RecordingSink.new
      given = { Keys::URL_FULL => "https://user:secret@h/p?sig=S&api-version=2",
                AUTHORIZATION => "Bearer CTXSECRET", LOCATION => "//u:p@evil/x?code=S",
                "service" => "pets", }
      logger = Logger.build(sink: sink, context: given)
      logger.event(Severity::INFO).field(:k, 1).emit
      payload = sink.payloads.first

      assert_equal("https://***:***@h/p?sig=***&api-version=2", payload[Keys::URL_FULL])
      assert_equal(Redactor::REDACTED_HEADER, payload[AUTHORIZATION])
      assert_equal("//***:***@evil/x?***", payload[LOCATION])
      assert_equal("pets", payload["service"])
      assert_equal(payload.except("k"), logger.context, "redacted once, at construction")
      refute_includes(sink.payloads.inspect, "secret")
      refute_includes(sink.payloads.inspect, "CTXSECRET")
      refute_includes(sink.payloads.inspect, "code=S")
      assert_equal("Bearer CTXSECRET", given[AUTHORIZATION], "the caller's Hash is untouched")
    end

    test "OBS-18, P5-104: in omit mode a non-allow-listed header in the context is dropped" do
      sink = RecordingSink.new
      policy = Policy::DEFAULT.with(omit_disallowed_headers: true)
      logger = Logger.build(sink: sink, redactor: Redactor.build(policy: policy),
                            context: { AUTHORIZATION => "Bearer CTXSECRET", "who" => "ctx" },)
      logger.event(Severity::INFO).emit

      assert_equal({ "who" => "ctx" }, logger.context)
      assert_equal({ "who" => "ctx" }, sink.payloads.first)
    end

    test "OBS-39, OBS-18, OBS-10, P5-104: reserved keys in the unfiltered fold are redacted" do
      sink = RecordingSink.new
      DiagnosticContext.preserve do
        ::Fiber[:"url.full"] = "https://user:secret@h/p?sig=S"
        ::Fiber[AUTHORIZATION.to_sym] = "Bearer FIBSECRET"
        ::Fiber[:"http.request.header.content-type"] = "text/plain"
        ::Fiber[:"trace.id"] = "t1"
        Logger.build(sink: sink, diagnostic_keys: nil).event(Severity::INFO).emit
        listing = Logger.build(sink: sink, diagnostic_keys: [:"url.full", AUTHORIZATION.to_sym])
        listing.event(Severity::INFO).emit
      end
      unfiltered, listed = sink.payloads

      assert_equal({ Keys::URL_FULL => "https://***:***@h/p?sig=***",
                     AUTHORIZATION => Redactor::REDACTED_HEADER,
                     "http.request.header.content-type" => "text/plain", "trace.id" => "t1", },
                   unfiltered,)
      assert_equal({ Keys::URL_FULL => "https://***:***@h/p?sig=***",
                     AUTHORIZATION => Redactor::REDACTED_HEADER, }, listed,)
      refute_includes(sink.payloads.inspect, "secret")
      refute_includes(sink.payloads.inspect, "FIBSECRET")
    end

    test "OBS-18, P5-104: the fold honours omit mode, and a per-event field still wins" do
      sink = RecordingSink.new
      policy = Policy::DEFAULT.with(omit_disallowed_headers: true)
      logger = Logger.build(sink: sink, redactor: Redactor.build(policy: policy),
                            diagnostic_keys: nil,)
      DiagnosticContext.preserve do
        ::Fiber[AUTHORIZATION.to_sym] = "Bearer FIBSECRET"
        ::Fiber[:"url.full"] = "https://user:secret@h/p"
        logger.event(Severity::INFO).field(Keys::URL_FULL, "https://u2:p2@field/q?sig=F").emit
      end

      assert_equal({ Keys::URL_FULL => "https://***:***@field/q?sig=***" }, sink.payloads.first)
    end
  end
end
