# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/transport/net_http"
require "openssl"
require "zlib"
require "socket"

# TRANSPORT-3: "Discrimination MUST be out-of-band ... not by matching exception messages."
# TRANSPORT-4: a read timeout classifies retryable and MUST NOT set the cancellation flag.
# TRANSPORT-20: the canonical retryable transport failure, for anything that produced no
# response. P6-4's obligation: wrap, and default to retryable -- a CATCH-ALL, never a lookup
# against a list, because a family nobody thought of escaping unwrapped classifies not-retryable.
class DexpaceTransportNetHttpFailuresTest < DexpaceTestCase
  Failures = Dexpace::Transport::NetHTTP.const_get(:Failures)

  # The families the adapter actually meets (design, verified fact 7): none but EOFError and
  # IOError is an ::IOError, which is why an unwrapped one would be P6-4's blind spot.
  FAMILIES = [
    ::Net::OpenTimeout, ::Net::ReadTimeout, ::Net::WriteTimeout, ::SocketError,
    ::Errno::ECONNRESET, ::Errno::ECONNREFUSED, ::OpenSSL::SSL::SSLError, ::EOFError, ::IOError,
    ::Net::HTTPBadResponse, ::Net::HTTPHeaderSyntaxError, ::Zlib::DataError,
  ].freeze

  def uncancelled
    Dexpace::Cancellation.none
  end

  # Failures.wrap RETURNS the error and never assigns #cause: Ruby populates #cause from `$!`
  # at the raise, so the production call site raises from inside its own rescue. This helper
  # reproduces that context so the cause assertion below is the real one.
  def wrap_and_capture(original, phase: :read, cancellation: uncancelled)
    raise original
  rescue original.class => error
    begin
      raise Failures.wrap(error, phase: phase, cancellation: cancellation)
    rescue Dexpace::TransportError => wrapped
      wrapped
    end
  end

  test "is a private_constant of NetHTTP" do
    assert_raises(NameError) { Dexpace::Transport::NetHTTP::Failures }
  end

  FAMILIES.each do |klass|
    test "wraps #{klass} into a retryable Dexpace::TransportError carrying it as #cause" do
      original = klass.new("boom")

      wrapped = wrap_and_capture(original)

      assert_instance_of(Dexpace::TransportError, wrapped)
      assert_predicate(wrapped, :retryable?)
      assert_same(original, wrapped.cause)
      assert_equal(:read, wrapped.phase)
      assert_equal(original.message, wrapped.message)
    end
  end

  test "only EOFError and IOError of the documented families are ::IOErrors (P6-4's blind spot)" do
    io_errors = FAMILIES.select { |klass| klass <= ::IOError }

    assert_equal([::EOFError, ::IOError], io_errors)
  end

  test "TRANSPORT-3: asks the cancellation token first, regardless of the exception's class" do
    source = Dexpace::Cancellation.source
    source.cancel(:caller_requested)

    closed = ::IOError.new("stream closed in another thread")

    wrapped = Failures.wrap(closed, phase: :read, cancellation: source.token)

    assert_instance_of(Dexpace::CancelledError, wrapped)
    assert_equal(:caller_requested, wrapped.reason)
  end

  test "TRANSPORT-3: a cancelled token wins even over a Dexpace::Error of the adapter's own" do
    source = Dexpace::Cancellation.source
    source.cancel(:gave_up)

    wrapped = Failures.wrap(Dexpace::ClosedError.new("closed"), phase: :read,
                                                                cancellation: source.token,)

    assert_instance_of(Dexpace::CancelledError, wrapped)
  end

  test "TRANSPORT-4: a read timeout does not itself set the cancellation flag" do
    source = Dexpace::Cancellation.source

    wrapped = Failures.wrap(::Net::ReadTimeout.new("slow"), phase: :read,
                                                            cancellation: source.token,)

    refute_predicate(source, :cancelled?)
    assert_predicate(wrapped, :retryable?)
  end

  test "never re-wraps a Dexpace::Error the adapter's own code raised" do
    own_errors = [Dexpace::StreamError.new("x"), Dexpace::ClosedError.new("x"),
                  Dexpace::EndOfStreamError.new("x"), Dexpace::InvalidArgumentError.new("x"),
                  Dexpace::TransportError.new("x", phase: :read),]
    own_errors.each do |own|
      wrapped = Failures.wrap(own, phase: :read, cancellation: uncancelled)

      assert_same(own, wrapped)
    end
  end

  test "an unrecognised StandardError still wraps retryable, per the design's own default" do
    wrapped = Failures.wrap(::RuntimeError.new("unexpected"), phase: :connect,
                                                              cancellation: uncancelled,)

    assert_instance_of(Dexpace::TransportError, wrapped)
    assert_predicate(wrapped, :retryable?)
    assert_equal(:connect, wrapped.phase)
  end

  test "the wrapped error answers RETRY-2's capability query through the policy" do
    wrapped = wrap_and_capture(::Net::OpenTimeout.new("connect"))

    assert(Dexpace::Resilience::Policy.throwable_retryable?(wrapped))
  end
end
