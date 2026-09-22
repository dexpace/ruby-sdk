# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace/transport/async_http"

# Dispatch step 17's classifier. P6-4: "wrap, and default to retryable" -- not one of the
# families async-http raises is an ::IOError but EOFError and IOError (the design's verified fact
# 11), so every one needs Dexpace::TransportError to answer #retryable? at all. TRANSPORT-3: the
# token is asked first, never the exception. P3-3: a body failure after the head is a
# StreamError, a sibling of TransportError and never its descendant.
class DexpaceTransportAsyncHTTPErrorsTest < DexpaceTestCase
  Errors = Dexpace::Transport::AsyncHTTP.const_get(:Errors, false)

  NATIVE = [
    ::Async::TimeoutError.new("execution expired"),
    ::Errno::ECONNREFUSED.new,
    ::SocketError.new("getaddrinfo: Name or service not known"),
    ::OpenSSL::SSL::SSLError.new("certificate verify failed"),
    ::EOFError.new("end of file reached"),
    ::IOError.new("stream closed in another thread"),
    ::Protocol::HTTP::RefusedError.new("bad header"),
    ::Protocol::HTTP::RemoteError.new("peer reset"),
    ::Protocol::HTTP1::BadRequest.new("Invalid content length"),
    ::NoMethodError.new("undefined method 'readpartial' for nil"),
    ::RuntimeError.new("a family nobody thought of"),
  ].freeze

  def none = Dexpace::Cancellation.none

  test "TRANSPORT-4/TRANSPORT-20: every native family wraps into a retryable TransportError " \
       "carrying the original as #cause and the phase given" do
    NATIVE.each do |native|
      wrapped = Errors.wrap(native, phase: :connect, cancellation: none)

      assert_instance_of(Dexpace::TransportError, wrapped, native.class.to_s)
      assert_predicate(wrapped, :retryable?, native.class.to_s)
      assert_same(native, wrapped.cause, native.class.to_s)
      assert_equal(:connect, wrapped.phase)
      assert_includes(wrapped.message, native.message)
    end
  end

  # The SDK's own errors are in the list too: a ClosedError out of a connection the watcher
  # retired arrives under a cancelled token, and the token still wins -- the pass-through below is
  # for an UNCANCELLED token only, so an implementation that consulted the class first survives
  # every native family and fails exactly here.
  test "TRANSPORT-3: asks the cancellation token first -- a cancelled token turns any error " \
       "into CancelledError with the token's reason, an IOError and a Dexpace:: error included" do
    source = Dexpace::Cancellation.source
    source.cancel(:caller_gave_up)

    ours = [Dexpace::ClosedError.new("retired"), Dexpace::StreamError.new("torn")]
    (NATIVE + ours).each do |native|
      wrapped = Errors.wrap(native, phase: :read, cancellation: source.token)

      assert_instance_of(Dexpace::CancelledError, wrapped, native.class.to_s)
      assert_equal(:caller_gave_up, wrapped.reason)
      refute_respond_to(wrapped, :retryable?)
    end
  end

  test "a Dexpace:: error is passed through unwrapped, unchanged, with no cause added" do
    [Dexpace::StreamError.new("already ours"), Dexpace::InvalidArgumentError.new("HTTP-17"),
     Dexpace::ClosedError.new("closed"),].each do |original|
      assert_same(original, Errors.wrap(original, phase: :connect, cancellation: none))
      assert_nil(original.cause)
    end
  end

  test "is callable standalone, with no ambient rescue in flight" do
    # No begin/rescue anywhere above this line: $! is nil here, and #wrap must still attach the
    # argument as #cause rather than depending on an ambient in-flight exception.
    wrapped = Errors.wrap(::EOFError.new("no ambient rescue"), phase: :connect, cancellation: none)

    assert_kind_of(::EOFError, wrapped.cause)
  end

  test "TRANSPORT-4 never writes to the token: a deadline leaves the flag clear" do
    source = Dexpace::Cancellation.source
    Errors.wrap(::Async::TimeoutError.new("execution expired"), phase: :connect,
                                                                cancellation: source.token,)

    refute_predicate(source.token, :cancelled?)
  end

  test "P3-3: a mid-stream body failure classifies as StreamError, the token first, never " \
       "TransportError" do
    eof = ::EOFError.new("end of file reached")
    classified = Errors.classify_read(eof, cancellation: none)

    assert_instance_of(Dexpace::StreamError, classified)
    assert_same(eof, classified.cause)
    refute_respond_to(classified, :retryable?)
    refute_operator(Dexpace::StreamError, :<, Dexpace::TransportError)

    source = Dexpace::Cancellation.source
    source.cancel(:mid_body)

    assert_instance_of(Dexpace::CancelledError,
                       Errors.classify_read(eof, cancellation: source.token),)
  end

  # ASYNC-6: only Completer#request_cancel produces the settlement Future#cancelled? reads as
  # true; a failure carrying a CancelledError instance would leave it false.
  test "settle routes a cancelled token to #request_cancel and everything else to #fail" do
    source = Dexpace::Cancellation.source
    source.cancel(:gone)
    cancelled = Dexpace::Async::Completer.new
    Errors.settle(cancelled, ::EOFError.new, phase: :connect, cancellation: source.token)

    assert_predicate(cancelled.future, :cancelled?)
    assert_equal(:gone, assert_raises(Dexpace::CancelledError) { cancelled.future.value }.reason)

    failed = Dexpace::Async::Completer.new
    Errors.settle(failed, ::EOFError.new, phase: :connect, cancellation: none)

    refute_predicate(failed.future, :cancelled?)
    assert_predicate(assert_raises(Dexpace::TransportError) { failed.future.value }, :retryable?)
  end

  test "never sees Async::Cancel, by construction" do
    # Errors.wrap is only ever called from a `rescue ::StandardError` arm, which Async::Cancel
    # (< Exception) cannot reach; this documents the invariant the arms rest on.
    refute_operator(::Async::Cancel, :<, ::StandardError)
    assert_operator(::Async::TimeoutError, :<, ::StandardError)
    assert_same(::Async::Stop, ::Async::Cancel)
  end
end
