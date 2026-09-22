# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "socket"

# Accepts, reads the request and writes NOTHING: the client blocks waiting for the status line,
# which is the phase TRANSPORT-8's pair needs to hold -- before `Client#call` has returned
# anything at all -- for both a parent task's cancellation and a deadline. Retired the way
# AsyncHTTPHoldingServer is: by closing the queue and the listener, never by an interrupt.
class AsyncHTTPSilentServer
  def initialize
    @server = ::TCPServer.new("127.0.0.1", 0)
    @accepted = ::Thread::Queue.new
    @gate = ::Thread::Queue.new
    @thread = ::Thread.new { serve }
  end

  def port = @server.addr[1]

  # Blocks until a connection was accepted and its request read -- the client is now waiting.
  def wait_for_accept = @accepted.pop

  def close
    @gate.close
    @server.close
    @thread.join(2)
    nil
  end

  private

  def serve
    socket = @server.accept
    request = +""
    request << socket.readpartial(4096) until request.include?("\r\n\r\n")
    @accepted.push(true)
    @gate.pop # parks until #close closes the queue
  rescue ::IOError, ::Errno::EBADF, ::Errno::ECONNRESET, ::Errno::EPIPE, ::ClosedQueueError
    nil
  ensure
    socket&.close
  end
end
