# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "socket"

# A raw TCPServer that decides when the client leaves a blocked state, so a cancellation test
# needs no sleep to "get into" it: it provokes the cancellation only after this server confirms
# (through `#wait_for_accept`) that it is holding the connection open. Two modes, one class:
# `hold: :head` writes a partial status line and headers and holds before the blank line, so the
# client is blocked waiting for the HEAD (the exchange task is in flight); `hold: :body` writes a
# complete chunked head and one chunk and holds before the next, so the head has been delivered
# and the CONSUMER is blocked in a body read.
#
# No Thread#kill anywhere: phase 0's Dexpace/NoThreadInterrupt cop is enabled repository-wide
# and a gem's own test/support/ file is scanned like any other. The handler thread is retired by
# closing what it is blocked on -- Thread::Queue#close wakes a blocked #pop with nil and
# TCPServer#close wakes a blocked #accept with IOError -- and joined with a bound, so
# DexpaceTestCase's per-test thread count is satisfied. Every response it writes is
# `Connection: close`, because the handler closes the socket after one exchange and a keep-alive
# connection the client's pool would reuse is the stale-connection race 8c's checklist records.
class AsyncHTTPHoldingServer
  def initialize(hold: :head)
    @hold = hold
    @server = ::TCPServer.new("127.0.0.1", 0)
    @gate = ::Thread::Queue.new
    @accepted = ::Thread::Queue.new
    @thread = ::Thread.new { serve }
  end

  def port = @server.addr[1]

  # Blocks the calling thread or fiber until this server has accepted a connection and written
  # what it writes before holding. Safe to call from inside a reactor: the pop is scheduler-aware
  # there, and this server's thread is not the reactor's.
  def wait_for_accept
    @accepted.pop
  end

  # Lets the held response finish with the given body (the second chunk, in body mode).
  def release(body = "released")
    @gate.push(body)
  end

  def close
    @gate.close
    @server.close
    @thread.join(2)
    nil
  end

  private

  def serve
    socket = @server.accept
    read_request(socket)
    @hold == :body ? hold_body(socket) : hold_head(socket)
  rescue ::IOError, ::Errno::EBADF, ::Errno::ECONNRESET, ::Errno::EPIPE, ::ClosedQueueError
    nil
  ensure
    socket&.close
  end

  def read_request(socket)
    request = +""
    request << socket.readpartial(4096) until request.include?("\r\n\r\n")
  end

  def hold_head(socket)
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nConnection: close\r\n")
    socket.flush
    @accepted.push(true)
    body = @gate.pop # nil once #close has closed the queue: the fixture is shutting down
    socket.write("Content-Length: #{body.bytesize}\r\n\r\n#{body}") if body
  end

  def hold_body(socket)
    socket.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nTransfer-Encoding: chunked\r\n" \
                 "Connection: close\r\n\r\n5\r\nfirst\r\n")
    socket.flush
    @accepted.push(true)
    body = @gate.pop
    socket.write("#{body.bytesize.to_s(16)}\r\n#{body}\r\n0\r\n\r\n") if body
  end
end
