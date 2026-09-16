# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-44, HTTP-45.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: HTTP-44's
# raw accessors and memo here, then Serialization (HTTP-45), Settlement and Construction below.
class DexpaceTypedResponseTest < DexpaceTestCase
  # The handler contract is #call(response) and nothing more, so the failure a handler raises
  # is the handler's own class. Phase 3b defines no serde error and names none.
  class HandlerFailure < ::StandardError; end

  # One shared factory set for every class below.
  module Typed
    def response(body: nil, status: 200)
      request = Dexpace::Request.builder
      request.url = "https://example.test/"
      builder = Dexpace::Response.builder
      builder.request = request.build
      builder.protocol = Dexpace::Protocol::HTTP_1_1
      builder.status = Dexpace::Status.of(status)
      builder.reason = "Fine"
      builder.body = body
      builder.build
    end

    def response_body(content = "héllo")
      Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(content))
    end

    def typed(handler, **rest)
      Dexpace::TypedResponse.new(response: response(**rest), handler: handler)
    end
  end
  include Typed

  # ---- HTTP-44: the raw accessors, without consuming the body -------------------------------

  test "exposes status, headers, protocol, reason and request without running the handler" do
    calls = 0
    subject = typed(->(_response) { calls += 1 })

    assert_equal(Dexpace::Status.of(200), subject.status)
    assert_equal(Dexpace::Headers::EMPTY, subject.headers)
    assert_equal(Dexpace::Protocol::HTTP_1_1, subject.protocol)
    assert_equal("Fine", subject.reason)
    assert_equal("https://example.test/", subject.request.url.to_s)
    assert_equal(0, calls)
  end

  test "the raw accessors do not consume the body" do
    body = response_body
    subject = Dexpace::TypedResponse.new(response: response(body: body), handler: ->(_r) {})
    subject.status
    subject.headers
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)

    assert_equal("héllo".b, sink.snapshot)
  end

  test "exposes the wrapped response itself" do
    wrapped = response
    subject = Dexpace::TypedResponse.new(response: wrapped, handler: ->(_r) { :ok })

    assert_same(wrapped, subject.response)
  end

  # ---- HTTP-44: the memo -------------------------------------------------------------------

  test "runs the handler at most once and returns the same value on every access" do
    calls = 0
    subject = typed(lambda { |_response|
      calls += 1
      Object.new
    })
    first = subject.value

    assert_same(first, subject.value)
    assert_same(first, subject.value)
    assert_equal(1, calls)
  end

  # THE `@value ||=` bug: a handler that legitimately decodes to nil would be re-run on every
  # access, and the second run would read a single-use body that is already gone. Asserted by
  # COUNTING invocations rather than by comparing a nil to a nil.
  test "memoises a nil success, so a handler that decodes to nil still runs exactly once" do
    calls = 0
    subject = typed(lambda { |_response|
      calls += 1
      nil
    })

    assert_nil(subject.value)
    assert_nil(subject.value)
    assert_nil(subject.value)
    assert_equal(1, calls)
  end

  test "memoises a false success too" do
    calls = 0
    subject = typed(lambda { |_response|
      calls += 1
      false
    })

    refute(subject.value)
    refute(subject.value)
    assert_equal(1, calls)
  end

  test "memoises a raised failure and re-raises the same object every time" do
    calls = 0
    subject = typed(lambda { |_response|
      calls += 1
      raise HandlerFailure, "bad json"
    })
    first = assert_raises(HandlerFailure) { subject.value }
    second = assert_raises(HandlerFailure) { subject.value }

    assert_same(first, second)
    assert_equal(1, calls)
  end

  # A bare `raise` re-raises the SAME object with its #cause and original backtrace intact,
  # verified on 3.2.11, 3.4.10 and 4.0.6.
  test "the re-raised failure keeps its cause and its original backtrace" do
    subject = typed(lambda { |_response|
      begin
        raise "root cause"
      rescue ::RuntimeError
        raise HandlerFailure, "decode failed"
      end
    })
    first = assert_raises(HandlerFailure) { subject.value }
    second = assert_raises(HandlerFailure) { subject.value }

    assert_equal("root cause", second.cause.message)
    assert_equal(first.backtrace, second.backtrace)
  end

  test "does not consume the body itself, leaving that to the handler" do
    body = response_body
    subject = Dexpace::TypedResponse.new(response: response(body: body), handler: ->(_r) { :ok })
    subject.value
    sink = Dexpace::IO::Buffer.new
    body.write_to(sink)

    assert_equal("héllo".b, sink.snapshot)
  end

  test "hands the whole response to the handler, which is what makes it status-aware" do
    seen = nil
    typed(->(r) { seen = r }, status: 503).value

    assert_equal(Dexpace::Status.of(503), seen.status)
  end

  # HTTP-45: serialization.
  class SerializationTest < DexpaceTestCase
    include Typed

    test "concurrent first accesses run the handler exactly once and all get the same object" do
      calls = ::Thread::Mutex.new
      count = 0
      value = Object.new
      subject = typed(lambda { |_response|
        calls.synchronize { count += 1 }
        sleep(0.01)
        value
      })
      start = ::Thread::Queue.new
      results = ::Thread::Queue.new
      threads = Array.new(8) do
        ::Thread.new do
          start.pop
          results << subject.value
        end
      end
      8.times { start << :go }
      threads.each(&:join)
      collected = Array.new(8) { results.pop }

      assert_equal(1, count)
      assert_equal([value], collected.uniq)
    end

    test "concurrent first accesses to a failing handler all raise the same object" do
      count = ::Thread::Mutex.new
      calls = 0
      subject = typed(lambda { |_response|
        count.synchronize { calls += 1 }
        sleep(0.01)
        raise HandlerFailure, "bad json"
      })
      start = ::Thread::Queue.new
      results = ::Thread::Queue.new
      threads = Array.new(8) do
        ::Thread.new do
          start.pop
          subject.value
        rescue HandlerFailure => error
          results << error
        end
      end
      8.times { start << :go }
      threads.each(&:join)
      collected = Array.new(8) { results.pop }

      assert_equal(1, calls)
      assert_equal(1, collected.uniq.length)
    end

    # A fiber suspended INSIDE the parse must not block a second fiber reading a raw accessor. That
    # is HTTP-44's "without consuming the body" made mechanical: under an implementation that took
    # the lock in the raw accessors, the second fiber would raise "ThreadError: deadlock; lock
    # already owned by another fiber belonging to the same thread".
    test "a fiber suspended mid-parse does not block another fiber reading a raw accessor" do
      subject = typed(lambda { |_response|
        ::Fiber.yield
        :parsed
      })
      parser = ::Fiber.new { subject.value }
      parser.resume

      observed = ::Fiber.new { [subject.status, subject.reason] }.resume
      parser.resume

      assert_equal([Dexpace::Status.of(200), "Fine"], observed)
      assert_equal(:parsed, subject.value)
    end

    # HTTP-44's "WITHOUT consuming the body" made mechanical on the lock rather than on the body: a
    # raw accessor that took the parse lock would block for the whole parse. Joined with a timeout,
    # because the failure mode of that bug is a hang and a hang is worse than a failure in CI.
    test "the raw accessors answer while another thread holds the parse lock" do
      subject = typed(->(_response) { :parsed })
      held = ::Thread::Queue.new
      release = ::Thread::Queue.new
      holder = ::Thread.new do
        subject.instance_variable_get(:@mutex).synchronize do
          held << :held
          release.pop
        end
      end
      held.pop
      reader = ::Thread.new { [subject.status, subject.reason, subject.headers] }
      finished = reader.join(5)
      release << :go
      holder.join
      reader.join

      refute_nil(finished, "a raw accessor blocked on the parse lock")
      assert_equal([Dexpace::Status.of(200), "Fine", Dexpace::Headers::EMPTY], reader.value)
    end

    test "two fibers of one thread reach the memo without a recursive-lock ThreadError" do
      calls = 0
      subject = typed(lambda { |_response|
        calls += 1
        :parsed
      })
      first = ::Fiber.new { subject.value }.resume
      second = ::Fiber.new { subject.value }.resume

      assert_equal(:parsed, first)
      assert_equal(:parsed, second)
      assert_equal(1, calls)
    end
  end

  # The memo's settlement when the handler fails outside StandardError.
  class SettlementTest < DexpaceTestCase
    include Typed

    # A handler that raises OUTSIDE StandardError unwinds past the ordinary rescue; the state must
    # not stay :running, or every later caller waits on the condition variable for the life of the
    # process. The failure is re-raised unchanged, so nothing is swallowed.
    test "a handler raising outside StandardError still settles the state, so no caller hangs" do
      subject = typed(->(_response) { raise ::NotImplementedError, "broken handler" })

      assert_raises(::NotImplementedError) { subject.value }
      later = ::Thread.new do
        subject.value
      rescue ::NotImplementedError => error
        error
      end
      finished = later.join(5)

      refute_nil(finished, "a later caller hung on an unsettled parse")
      assert_instance_of(::NotImplementedError, later.value)
    end
  end

  # Construction.
  class ConstructionTest < DexpaceTestCase
    include Typed

    # A lambda IS the handler contract, which is why the test double is one line and needs no
    # support class. Phase 7 supplies a status-aware handler INTO this rather than replacing it.
    test "accepts any object responding to call, and a lambda is one" do
      callable = Class.new { def call(_response) = :ok }.new

      assert_equal(:ok, typed(callable).value)
      assert_equal(:ok, typed(->(_r) { :ok }).value)
    end

    test "rejects a handler that does not respond to call" do
      error = assert_raises(Dexpace::InvalidArgumentError) { typed(Object.new) }

      assert_includes(error.message, "#call(response)")
    end

    test "rejects anything that is not a Dexpace::Response" do
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::TypedResponse.new(response: :not_a_response, handler: ->(_r) { :ok })
      end

      assert_includes(error.message, "Dexpace::Response")
    end
  end
end
