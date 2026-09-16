# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"
require_relative "../../../support/fake_body"
require_relative "../../../support/fake_sink"

# BODY-17, BODY-18, BODY-19, BODY-20, BODY-21, BODY-34, BODY-37.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: BODY-17
# and BODY-19 here, then Attempts, Replay and Surface below.
class DexpaceRequestLoggingBodyTest < DexpaceTestCase
  # One shared factory for every class below.
  module Wrappers
    def wrapper(delegate = FakeBody.new("hé", "llo"), **rest)
      Dexpace::RequestLoggingBody.new(delegate, **rest)
    end
  end
  include Wrappers

  # A #write sink that also answers #close, #flush and #emit, so "IO-29 forwards all three to the
  # primary and the wrapper therefore calls none of them" is measurable rather than described.
  class RecordingSink
    attr_reader :closes, :flushes, :emits, :written

    def initialize
      @closes = 0
      @flushes = 0
      @emits = 0
      @written = +"".b
    end

    def write(*strings)
      payload = strings.join.b
      @written << payload
      payload.bytesize
    end

    def close = @closes += 1
    def flush = @flushes += 1
    def emit = @emits += 1
  end

  # ---- BODY-17: mirror while forwarding, consuming the upstream once ------------------------

  test "forwards every byte to the primary sink" do
    sink = FakeSink.new
    wrapper.write_to(sink)

    assert_equal("héllo".b, sink.written)
  end

  test "mirrors the exact bytes the delegate's single write produced" do
    subject = wrapper
    subject.write_to(FakeSink.new)

    assert_equal("héllo".b, subject.snapshot)
  end

  test "consumes the upstream exactly once, never twice" do
    delegate = FakeBody.new("hé", "llo")
    wrapper(delegate).write_to(FakeSink.new)

    assert_equal(1, delegate.writes)
  end

  test "the full untruncated payload reaches the primary whatever the tap cap is" do
    sink = FakeSink.new
    subject = wrapper(FakeBody.new("hé", "llo"), tap_limit: 2)
    subject.write_to(sink)

    assert_equal("héllo".b, sink.written)
    assert_equal("hé".b[0, 2], subject.snapshot)
  end

  test "reports the byte count the delegate's write returned" do
    assert_equal(6, wrapper.write_to(FakeSink.new))
  end

  # ---- BODY-19: the bounded tap, and its unbounded default ---------------------------------

  # BODY-19 states this default in its own text, and it is DELIBERATELY asymmetric with
  # ResponseLoggingBody's required preview_bytes: (P3-18). Unifying the two breaks a requirement.
  test "defaults its tap cap to unbounded, which BODY-19 states outright" do
    parameters = Dexpace::RequestLoggingBody.instance_method(:initialize).parameters

    assert_includes(parameters, %i[key tap_limit])
    assert_equal("héllo".b, wrapper.tap { |w| w.write_to(FakeSink.new) }.snapshot)
  end

  test "stops copying into the tap once the cap is reached" do
    subject = wrapper(FakeBody.new("0123456789"), tap_limit: 4)
    subject.write_to(FakeSink.new)

    assert_equal(4, subject.tap_bytesize)
    assert_equal("0123".b, subject.snapshot)
  end

  test "a tap cap of zero mirrors nothing and still forwards everything" do
    sink = FakeSink.new
    subject = wrapper(FakeBody.new("héllo"), tap_limit: 0)
    subject.write_to(sink)

    assert_equal("héllo".b, sink.written)
    assert_equal("".b, subject.snapshot)
  end

  test "rejects a negative or fractional tap cap at construction, as the tee does" do
    assert_raises(Dexpace::InvalidArgumentError) { wrapper(tap_limit: -1) }
    assert_raises(Dexpace::InvalidArgumentError) { wrapper(tap_limit: 1.5) }
  end

  # BODY-18: satisfied by construction, with a FRESH tee per write.
  class AttemptsTest < DexpaceTestCase
    include Wrappers

    # A fresh tee per write cannot accumulate an earlier attempt's bytes, which is strictly
    # stronger than clearing one -- it also drops the previous attempt's memory. It is why 3a
    # dropped TeeSink#clear_tap (3a's checklist, deviation 1).
    test "a retry against a replayable delegate does not accumulate the earlier attempt's bytes" do
      subject = wrapper(FakeBody.new("héllo", replayable: true))
      subject.write_to(FakeSink.new)
      subject.write_to(FakeSink.new)

      assert_equal("héllo".b, subject.snapshot)
    end

    test "builds a different tee for every write, so no state survives an attempt" do
      subject = wrapper(FakeBody.new("héllo", replayable: true))
      subject.write_to(FakeSink.new)
      first = subject.instance_variable_get(:@tee)
      subject.write_to(FakeSink.new)

      refute_same(first, subject.instance_variable_get(:@tee))
    end

    test "never calls close, flush or emit on the tee, because IO-29 forwards all three" do
      primary = RecordingSink.new
      wrapper.write_to(primary)

      assert_equal("héllo".b, primary.written)
      assert_equal(0, primary.closes)
      assert_equal(0, primary.flushes)
      assert_equal(0, primary.emits)
    end

    test "a write that fails partway still leaves the mirrored bytes in the snapshot" do
      subject = wrapper(FakeBody.new("hé", "llo", fail_after: 1))

      assert_raises(Dexpace::StreamError) { subject.write_to(FakeSink.new) }
      assert_equal("hé".b, subject.snapshot)
    end

    # IO-27's ordering is what makes this true: the tee mirrors BEFORE it forwards, so a
    # PRIMARY-side failure still leaves the failing chunk captured.
    test "a primary-side failure still leaves the failing chunk captured" do
      subject = wrapper(FakeBody.new("hé", "llo"))
      exploding = FakeSink.new("hé".bytesize, Dexpace::StreamError.new("the socket went away"))

      assert_raises(Dexpace::StreamError) { subject.write_to(exploding) }
      assert_equal("héllo".b, subject.snapshot)
    end

    test "the snapshot before any write is an empty BINARY String" do
      assert_equal("".b, wrapper.snapshot)
      assert_equal(::Encoding::BINARY, wrapper.snapshot.encoding)
      assert_equal(0, wrapper.tap_bytesize)
    end
  end

  # BODY-21: replayability verbatim, and a wrapper around the replayable form.
  class ReplayTest < DexpaceTestCase
    include Wrappers

    test "exposes the delegate's replayability verbatim" do
      refute_predicate(wrapper(FakeBody.new("a", replayable: false)), :replayable?)
      assert_predicate(wrapper(FakeBody.new("a", replayable: true)), :replayable?)
    end

    test "materialize-once returns a wrapper around the delegate's replayable form" do
      subject = wrapper(FakeBody.new("héllo"), tap_limit: 4)
      materialized = subject.to_replayable

      assert_instance_of(Dexpace::RequestLoggingBody, materialized)
      assert_predicate(materialized, :replayable?)
      assert_instance_of(Dexpace::BufferBody, materialized.delegate)
    end

    test "materialize-once preserves the tap cap, so a retry loop keeps capturing" do
      materialized = wrapper(FakeBody.new("0123456789"), tap_limit: 4).to_replayable
      materialized.write_to(FakeSink.new)

      assert_equal("0123".b, materialized.snapshot)
    end

    test "materialize-once returns self when the delegate is already replayable" do
      subject = wrapper(FakeBody.new("a", replayable: true))

      assert_same(subject, subject.to_replayable)
    end

    test "delegates the media type and the declared length" do
      media = Dexpace::MediaType.parse("text/plain")
      subject = wrapper(FakeBody.new("a", media_type: media, content_length: 1))

      assert_equal(media, subject.media_type)
      assert_equal(1, subject.content_length)
    end
  end

  # BODY-37's no-writable-buffer rule, construction, and BODY-34's structural half.
  class SurfaceTest < DexpaceTestCase
    include Wrappers

    # ONE mechanism, not two: the wrapper exposes no buffer accessor and TeeSink#buffer already
    # raises with the actionable message. Design §10.10 records the honest position -- the
    # prohibition cannot be language-enforced, instance_variable_get reaches anything -- and this
    # claims no more.
    test "exposes no buffer handle of its own" do
      refute_respond_to(wrapper, :buffer)
    end

    test "the tee's own buffer accessor fails loudly with an actionable message" do
      subject = wrapper
      subject.write_to(FakeSink.new)
      error = assert_raises(Dexpace::StreamError) { subject.instance_variable_get(:@tee).buffer }

      assert_includes(error.message, "IO-28")
    end

    test "rejects a delegate that cannot produce bytes" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::RequestLoggingBody.new(42) }

      assert_includes(error.message, "#write_to")
    end

    test "has no readable source, because it wraps a request body" do
      assert_raises(Dexpace::StreamError) { wrapper.source }
    end

    # BODY-34's enablement clause is satisfied STRUCTURALLY in phase 3b: nothing in core constructs
    # a logging wrapper, so the wrappers are off the path unless something builds one. Phase 5's
    # instrumentation layer is the thing that will (phase 5b, Tasks 14-15).
    test "nothing in the core library constructs a logging wrapper" do
      root = File.expand_path("../../../../lib", __dir__)
      sources = Dir.glob("#{root}/**/*.rb").grep_v(/request_logging_body\.rb\z/)
      constructions = sources.select do |path|
        File.read(path).include?("RequestLoggingBody.new")
      end

      assert_empty(constructions)
    end

    test "compares by value over its delegate and its cap" do
      delegate = FakeBody.new("a")

      assert_equal(wrapper(delegate, tap_limit: 4), wrapper(delegate, tap_limit: 4))
      assert_equal(wrapper(delegate, tap_limit: 4).hash, wrapper(delegate, tap_limit: 4).hash)
      refute_equal(wrapper(delegate, tap_limit: 4), wrapper(delegate, tap_limit: 8))
    end
  end
end
