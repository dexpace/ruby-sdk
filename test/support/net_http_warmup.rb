# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "net/http"
require "socket"

# net-http below 0.7 opens its connection inside Timeout.timeout (net/http.rb's #connect on
# 0.4.1 and 0.6.0, the default gems of Ruby 3.2, 3.3 and 3.4), and the FIRST Timeout.timeout in
# a process starts a process-wide singleton thread that lives for the rest of the process. 0.9.1,
# Ruby 4.0's, connects through TCPSocket.open(open_timeout:) and starts none. DexpaceTestCase
# counts threads around every test, so the first test to open a connection on a floor row would
# be charged with a thread it did not start and cannot join. One connection here, at load and
# before any count is taken, puts that thread where it belongs: outside every test. This is not
# the SDK's code -- the SDK never calls Timeout.timeout (design §8.3) -- and the interrupt lands
# on nothing, because the block returns at once. net-http's own use is on phase 10's inbound
# list (the phase-8a design's findings).
module NetHTTPWarmup
  # @return [nil]
  def self.run
    server = ::TCPServer.new("127.0.0.1", 0)
    accepter = ::Thread.new { server.accept.close }
    client = ::Net::HTTP.new("127.0.0.1", server.addr[1])
    client.open_timeout = 5
    client.start { nil }
    accepter.join(5)
    nil
  ensure
    server&.close
  end
end

NetHTTPWarmup.run
