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
#
# The client is built with an EXPLICIT nil proxy, exactly as the adapter builds its own
# (ProxyRoute, R17), and never with Net::HTTP.new's `:ENV` default. That default consults
# URI#find_proxy on `#start`, and uri (0.12.5 on the 3.2 floor through 1.1.1 on 4.0.6) warns
# "The environment variable HTTP_PROXY is discouraged" whenever HTTP_PROXY is set and the
# lower-case http_proxy is not -- BEFORE its loopback exemption and before NO_PROXY is read --
# which DexpaceTestCase turns into an error at load, in every suite of both gems (review round
# 2's R2-1). Every raw Net::HTTP a suite of this repository starts passes the same nil, so the
# suites are hermetic under HTTP_PROXY, http_proxy, HTTPS_PROXY and NO_PROXY alike; the two
# R17 controls in the adapter's suites reach `:ENV` on purpose and set http_proxy themselves.
module NetHTTPWarmup
  # @return [nil]
  def self.run
    server = ::TCPServer.new("127.0.0.1", 0)
    accepter = ::Thread.new { server.accept.close }
    client = ::Net::HTTP.new("127.0.0.1", server.addr[1], nil, nil, nil, nil)
    client.open_timeout = 5
    client.start { nil }
    accepter.join(5)
    nil
  ensure
    server&.close
  end
end

NetHTTPWarmup.run
