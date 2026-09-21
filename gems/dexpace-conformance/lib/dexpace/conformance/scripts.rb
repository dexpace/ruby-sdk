# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # Named response scripts a WireServer runs against every accepted connection. Each function
    # returns a callable taking the connection socket and the already-read request head (the
    # request line plus the header lines, an Array of raw String lines); the server has read and
    # recorded any request body before the script runs, so a script only writes.
    #
    # Every status line answers HTTP/1.1: phase 1's Protocol.parse has no alias for "http/1.0"
    # (8a plan, Task 17), and no TRANSPORT ID asks for 1.0. A script that must WAIT blocks on the
    # socket -- `wait_readable` for a delay, `readpartial` for "until the peer goes away" -- and
    # never on `sleep`, so WireServer#close, which closes every accepted socket, wakes it at once
    # and no handler thread outlives the test that started it.
    module Scripts
      extend self

      # A fixed-length body over ordinary framing: the script most assertions reach for. With
      # `hold: true` the connection is held open after the response until the PEER closes it, so
      # the fixture's #closed_connections counts the client's close rather than the handler's
      # finishing -- the only way "closing the response returns the connection" (TRANSPORT-22,
      # TRANSPORT-25) is observable from the server's side.
      #
      # @param body [String] the body bytes
      # @param status [String] the status line's code and reason
      # @param headers [Hash{String => String}] response headers beside Content-Length
      # @param hold [Boolean] whether to wait for the peer's close after answering
      # @return [Proc] the script
      def fixed(body, status: "200 OK", headers: { "Content-Type" => "text/plain" }, hold: false)
        lambda do |conn, _head|
          write_response(conn, status: status, headers: headers, body: body)
          drain_until_closed(conn) if hold
        end
      end

      # TRANSPORT-25's multi-megabyte body, in one write, over #large_body's bytes; `hold:` as
      # for #fixed.
      #
      # @param byte_count [Integer]
      # @param hold [Boolean] whether to wait for the peer's close after answering
      # @return [Proc] the script
      def large(byte_count, hold: false)
        fixed(large_body(byte_count), hold: hold)
      end

      # The bytes #large writes: a repeating alphabet cut to the count, so a byte-exact comparison
      # detects a dropped or duplicated chunk where a uniform "aaaa" body would not. BINARY, as
      # every wire byte is.
      #
      # @param byte_count [Integer]
      # @return [String] frozen, BINARY
      def large_body(byte_count)
        pattern = ("a".."z").to_a.join
        (pattern * ((byte_count / pattern.bytesize) + 1)).byteslice(0, byte_count).to_s.b.freeze
      end

      # TRANSPORT-19/TRANSPORT-25: a chunked body written in two pieces with a gap between them --
      # the shape that makes pre-buffering observable as a timing defect and not only a content
      # one. The gap is `wait_readable(delay_seconds)` on the connection, which returns early the
      # moment the peer closes, so a client that abandons the response is not waited for.
      #
      # @param first [String] the first chunk
      # @param second [String] the second chunk
      # @param delay_seconds [Numeric] the gap
      # @return [Proc] the script
      def dribble(first, second, delay_seconds)
        lambda do |conn, _head|
          conn.write("HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n" \
                     "Transfer-Encoding: chunked\r\n\r\n")
          conn.write(chunk(first))
          conn.flush
          conn.wait_readable(delay_seconds)
          conn.write("#{chunk(second)}0\r\n\r\n")
        end
      end

      # TRANSPORT-1: a raw 302 with a Location, which the transport must return and never follow.
      #
      # @param to [String] the Location value
      # @return [Proc] the script
      def redirect(to)
        ->(conn, _head) { write_response(conn, status: "302 Found", headers: { "Location" => to }) }
      end

      # TRANSPORT-24: a vendor or otherwise unusual status code, with a body.
      #
      # @param code [Integer] the status code
      # @param body [String] the body
      # @return [Proc] the script
      def vendor_status(code, body)
        ->(conn, _head) { write_response(conn, status: "#{code} Vendor", body: body) }
      end

      # TRANSPORT-14's whole conformance clause in one response: a control byte in a value, a
      # non-ASCII byte in a name, obs-text in a value, a repeated Set-Cookie, and a body.
      #
      # @return [Proc] the script
      def malformed_headers
        lambda do |conn, _head|
          conn.write(
            "HTTP/1.1 200 OK\r\nX-Ctl: a\x01b\r\nX-B\xE9d: y\r\nX-Obs: caf\xE9\r\n" \
            "Set-Cookie: a=1\r\nSet-Cookie: b=2\r\nContent-Length: 2\r\n\r\nhi".b,
          )
        end
      end

      # TRANSPORT-27 (8a's R4): a non-numeric Content-Length beside a malformed Content-Type, then a
      # body closed by connection close -- the shape Net::HTTP itself refuses to read.
      #
      # @return [Proc] the script
      def malformed_content_length
        lambda do |conn, _head|
          conn.write("HTTP/1.1 200 OK\r\nContent-Type: not a/;;media type\r\n" \
                     "Content-Length: abc\r\n\r\nhi")
        end
      end

      # TRANSPORT-3/TRANSPORT-4/TRANSPORT-5/TRANSPORT-6: reads the request and never answers,
      # simulating a dead server on the SEND path -- the head never arrives, so the send itself
      # times out or is cancelled; it blocks on the socket until the client goes away or
      # WireServer#close ends it, never on a sleep. `on_request_read:` is called once, on the
      # SERVER's thread, once the whole request has been read -- the instant the client is
      # blocked waiting for the head -- which is where a test that must fire a cancellation "while
      # the call is blocked" pushes into a queue, deterministically, instead of guessing a delay.
      #
      # @param on_request_read [#call, nil] the hook
      # @return [Proc] the script
      def hang_before_headers(on_request_read: nil)
        lambda do |conn, _head|
          on_request_read&.call
          drain_until_closed(conn)
        end
      end

      # The body-read twin: writes a chunked head and never a body, so the head arrives and the
      # first BODY read is what blocks. `on_headers_written:` fires once the head is flushed, on
      # the server's thread. The adapter's own suite uses it for a mid-body cancellation and for
      # the mid-stream deadline refresh (8a's R3).
      #
      # @param on_headers_written [#call, nil] the hook
      # @return [Proc] the script
      def hang_after_headers(on_headers_written: nil)
        lambda do |conn, _head|
          conn.write("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n")
          conn.flush
          on_headers_written&.call
          drain_until_closed(conn)
        end
      end

      # TRANSPORT-2/TRANSPORT-3: the first connection on this script's own counter is dropped
      # without an answer; every later one answers normally -- the shape "assert the native client
      # does not silently re-send" needs.
      #
      # @param body [String] what the later connections answer
      # @return [Proc] the script
      def fail_first_connection_then_succeed(body)
        attempt = 0
        mutex = ::Thread::Mutex.new
        lambda do |conn, _head|
          first = mutex.synchronize { (attempt += 1) == 1 }
          write_response(conn, body: body) unless first
        end
      end

      # A body shorter than its declared Content-Length, then the connection closes: a truncated
      # transfer, distinct from a clean connection-close-framed body.
      #
      # @param declared_length [Integer] the Content-Length written
      # @param actual_body [String] the bytes actually sent
      # @return [Proc] the script
      def truncated(declared_length:, actual_body:)
        lambda do |conn, _head|
          conn.write("HTTP/1.1 200 OK\r\nContent-Length: #{declared_length}\r\n\r\n#{actual_body}")
        end
      end

      # PAGE-36's per-call-options test: different bodies in call order over one server, the last
      # repeated, so a test can assert each call reached a distinct page.
      #
      # @param bodies [Array<String>]
      # @return [Proc] the script
      def sequenced(*bodies)
        index = 0
        mutex = ::Thread::Mutex.new
        lambda do |conn, _head|
          body = bodies[mutex.synchronize { (index += 1) - 1 }] || bodies.last
          write_response(conn, body: body)
        end
      end

      # TRANSPORT-29: answers with the request's own path, so a response matched to the wrong
      # request is visible as a body that names another path.
      #
      # @return [Proc] the script
      def echo_path
        ->(conn, head) { write_response(conn, body: head.first.to_s.split[1].to_s) }
      end

      # The one write primitive: a status line, the headers plus a computed Content-Length, and
      # the body. It does not close the connection -- WireServer#handle's ensure does, once, for
      # every connection whatever its script did.
      #
      # @param conn [Object] the accepted socket
      # @param status [String] the status line's code and reason
      # @param headers [Hash{String => String}] response headers
      # @param body [String] the body
      # @return [nil]
      def write_response(conn, status: "200 OK", headers: { "Content-Type" => "text/plain" },
                         body: "")
        lines = headers.merge("Content-Length" => body.bytesize.to_s)
          .map { |name, value| "#{name}: #{value}" }.join("\r\n")
        conn.write("HTTP/1.1 #{status}\r\n#{lines}\r\n\r\n".b, body.b)
        conn.flush
        nil
      end

      private

      def chunk(bytes)
        "#{bytes.bytesize.to_s(16)}\r\n#{bytes}\r\n"
      end

      # Blocks until the peer closes or the socket is closed under it: a client that gives up
      # (its read timeout, its cancellation) ends this at once, and so does WireServer#close.
      def drain_until_closed(conn)
        loop { conn.readpartial(4096) }
      rescue ::IOError, ::SystemCallError
        nil # EOFError is an IOError: the peer went away, which is the end this wait was for
      end
    end
  end
end
