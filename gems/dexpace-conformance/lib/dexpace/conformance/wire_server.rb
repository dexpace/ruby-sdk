# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "socket"
require "dexpace/closeable"
require_relative "scripts"
require_relative "wire_server/recorded_request"
require_relative "wire_server/request_reader"

module Dexpace
  module Conformance
    # Design §9.3's fixture: a plaintext-only TCPServer bound to 127.0.0.1:0, running one accept
    # loop on its own thread -- never on the fiber under test (suite contract 10) -- and handing
    # each connection, on a thread of its own, to a script. It records what a transport put on
    # the wire (#requests, head and body), how many connections it opened (#connections, so
    # TRANSPORT-2's "does not silently re-send" is a count and not an inference) and how many it
    # has finished (#closed_connections, so TRANSPORT-25's "closing returns the connection" is
    # observed from the server's side, under a script that holds the connection until the peer
    # closes). P8-9: it speaks no TLS and exercises no connect timeout, and the suite's report
    # preamble says so.
    #
    # Teardown is the whole of the fixture's own XCUT-13 and it is where a fixture written the
    # obvious way leaks: #close closes the listener (waking a blocked #accept), joins the accept
    # thread, closes EVERY accepted socket (waking a handler blocked in a read or a wait) and
    # joins every handler, each join bounded by JOIN_DEADLINE_SECONDS -- the same latch-wake-join
    # shape the adapter's response pump uses, so the fixture teaches the teardown idiom the code
    # it tests uses (8a's open question 4). A script therefore never sleeps: it waits on the
    # socket, which #close can wake.
    #
    # `#await_closed_connection` is the one wait every "has the server seen the close?" assertion
    # uses -- a Queue#pop fed from the handler's ensure, bounded when the caller says so, never a
    # sleep-poll over #closed_connections, which is load-sensitive and order-dependent
    # (testing/4ef070df).
    class WireServer
      # How long #close waits for the accept thread and each handler (XCUT-13: bounded, never an
      # unbounded join).
      JOIN_DEADLINE_SECONDS = 5.0

      private_class_method :new

      # Starts a server on an ephemeral port. With a block, closes it on any exit and returns the
      # block's value; without one the caller owns #close.
      #
      # @param script [#call] the response script, taking `(connection, head_lines)`
      # @return [WireServer, Object]
      def self.start(script)
        server = new(script)
        return server unless block_given?

        begin
          yield server
        ensure
          server.close
        end
      end

      def initialize(script)
        # Through an untyped local: rbs 4.2's `TCPServer#initialize: (?String host, Integer port)`
        # reads under Steep as a single optional positional, so the direct two-argument call is
        # refused by the checker and not by Ruby.
        server_class = ::TCPServer #: untyped
        @tcp = server_class.new("127.0.0.1", 0)
        @port = @tcp.addr[1]
        @script = script
        @requests = []
        @connections = 0
        @closed_connections = 0
        @sockets = []
        @handlers = []
        @closed_queue = ::Thread::Queue.new
        @mutex = ::Thread::Mutex.new
        @closed = false
        @accept_thread = ::Thread.new { accept_loop }
      end

      # The ephemeral port the listener bound -- read at construction, so it still answers after
      # #close: TRANSPORT-20's refused-connection assertion closes the fixture and then sends to it.
      #
      # @return [Integer]
      attr_reader :port

      # @return [Array<RecordedRequest>] every request read so far, in arrival order, a fresh list
      def requests
        @mutex.synchronize { @requests.dup }
      end

      # @return [Integer] connections accepted so far
      def connections
        @mutex.synchronize { @connections }
      end

      # @return [Integer] connections whose handler has finished and closed the socket
      def closed_connections
        @mutex.synchronize { @closed_connections }
      end

      # Blocks until `count` more connections have been finished by their handler, or until
      # `timeout:` seconds pass with one still open. A Queue#pop, timed or not, never a sleep-poll;
      # #close closes the queue, so a waiter that outlives the server gets nil rather than
      # hanging. The suite's assertions pass a bound, so a transport that never releases a
      # connection fails the assertion instead of hanging the run.
      #
      # @param count [Integer]
      # @param timeout [Integer, Float, nil] the bound in seconds, nil to wait indefinitely
      # @return [Integer, nil] #closed_connections once every awaited connection finished, or nil
      #   when the bound elapsed or the server closed first
      def await_closed_connection(count = 1, timeout: nil)
        count.times do
          return nil if @closed_queue.pop(timeout: timeout).nil?
        end
        closed_connections
      end

      # Idempotent and bounded. The latch flips under the mutex and nothing else does; everything
      # after it is a wake and a bounded join.
      #
      # @return [nil]
      def close
        first = @mutex.synchronize do
          if @closed
            false
          else
            @closed = true
          end
        end
        return nil unless first

        Dexpace.close_quietly(@tcp)
        @accept_thread.join(JOIN_DEADLINE_SECONDS)
        sockets, handlers = @mutex.synchronize { [@sockets.dup, @handlers.dup] }
        sockets.each { |socket| Dexpace.close_quietly(socket) }
        handlers.each { |handler| handler.join(JOIN_DEADLINE_SECONDS) }
        @closed_queue.close
        nil
      end

      private

      def accept_loop
        loop do
          conn = @tcp.accept
          handler = ::Thread.new(conn) { |socket| handle(socket) }
          admitted = @mutex.synchronize do
            @connections += 1
            @sockets << conn
            @handlers << handler
            !@closed
          end
          next if admitted

          # Accepted in the window between the latch and the listener's close: it is tracked and
          # will be closed and joined by #close's own pass, which took its snapshot after this
          # thread ended, so nothing is stranded.
          Dexpace.close_quietly(conn)
        end
      rescue ::IOError, ::Errno::EBADF
        nil # the listener was closed from #close; this thread's job is done
      end

      def handle(conn)
        request = RequestReader.read(conn)
        return if request.nil?

        @mutex.synchronize { @requests << request }
        @script.call(conn, request.head)
      rescue ::StandardError
        nil # a script that raises must not crash the accept loop or strand another connection
      ensure
        @mutex.synchronize { @closed_connections += 1 }
        Dexpace.close_quietly(conn)
        begin
          @closed_queue.push(true)
        rescue ::ClosedQueueError
          nil # the server closed first; nobody is waiting
        end
      end
    end
  end
end
