# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "async/http"
require "openssl"
require "socket"

# An in-process async-http server over plaintext HTTP/1.1, plaintext prior-knowledge HTTP/2, and
# a self-signed TLS endpoint negotiating HTTP/2 by real ALPN -- the HTTP/2 driver the design's
# R16 says only this gem can supply, because 8a's TCPServer fixture speaks HTTP/1.1 bytes only.
# Must be constructed inside a running reactor (Sync/Async): it spawns its accept loop on
# Async::Task.current, exactly as the adapter's own exchange does. It lives in this gem's
# test/support/ and never in dexpace-conformance, which declares dexpace-core and nothing else.
#
# Readiness needs no probe: `Task#async` runs the child eagerly to its first suspension point,
# and Async::HTTP::Server#run binds the listener before it first suspends in `accept`, so the
# port is accepting when `#initialize` returns. A bare TCPSocket probe would have made the h2
# server log a JSON "Invalid connection preface" warning to stderr through Console on every
# construction. The reactor starts no OS thread, so DexpaceTestCase's thread count is unmoved;
# `#close` cancels the accept task, without which the enclosing `Sync` block never returns.
#
# Generates its own certificate per run (the design's open question 6): an RSA-2048 keygen costs
# about 100 ms, cheap enough to pay every run and avoiding a cached artefact's own .gitignore
# and invalidation story.
class AsyncHTTPServerFixture
  attr_reader :client_endpoint, :cert_store, :certificate, :received

  # async-http's server lets an EOFError out of a request read escape its per-connection task,
  # which Console reports to stderr as a task failure. A peer that closes between the request
  # line and the end of the headers -- an exchange cancelled mid-send, which several suites here
  # do on purpose -- is exactly that, and it is the peer's doing and not the fixture's; seen
  # once in a hundred-odd runs on 4.0.6 under load (2026-09-21), so it is swallowed rather than
  # left as a rare line on stderr. A BadRequest is already ignored by the superclass.
  class QuietServer < ::Async::HTTP::Server
    def accept(...)
      super
    rescue ::EOFError
      nil
    end
  end

  private_constant :QuietServer

  # Three constructors, one fixture; each takes the app as a block from the native request to
  # `[status, headers, body]`, and records every request's header pairs in `#received`.
  def self.http1(&) = new(tls: false, http2: false, &)
  def self.plaintext(&) = new(tls: false, http2: true, &)
  def self.tls(&) = new(tls: true, http2: true, &)

  def initialize(tls:, http2:, &handler)
    port = free_port
    @received = []
    @handler = handler
    server_endpoint, @client_endpoint = endpoints(tls, http2, port)
    @task = ::Async::Task.current.async do
      QuietServer.new(method(:app), server_endpoint).run
    end
  end

  # @return [String] the fixture's origin, for a Dexpace::Request
  def url(path = "/")
    "#{@client_endpoint.url.scheme}://127.0.0.1:#{@client_endpoint.url.port}#{path}"
  end

  # `#cancel`, never the deprecated `#stop`. The accept loop runs in a CHILD of the task the
  # constructor spawned -- Async::HTTP::Server#run returns once its listeners are bound -- and a
  # cancel on that completed parent still reaches the running child (measured on 2.46.0).
  def close
    @task&.cancel
    nil
  end

  # Whether the accept loop and every per-listener child have finished, which is when the
  # listening socket is closed: a connect probe would race the kernel's backlog and see a reset.
  def closed?
    return true if @task.nil?

    @task.finished? && Array(@task.children).all?(&:finished?)
  end

  private

  def app(request)
    @received << request.headers.to_a
    status, headers, body = @handler.call(request)
    ::Protocol::HTTP::Response[status, headers, body]
  end

  # Endpoint.new over a URI::RFC3986_PARSER-parsed URI, never Endpoint.parse (design §3.5).
  def endpoints(tls, http2, port)
    if tls
      generate_certificate!
      uri = ::URI::RFC3986_PARSER.parse("https://127.0.0.1:#{port}")
      [::Async::HTTP::Endpoint.new(uri, ssl_context: server_ssl_context),
       ::Async::HTTP::Endpoint.new(uri, ssl_context: client_ssl_context),]
    else
      uri = ::URI::RFC3986_PARSER.parse("http://127.0.0.1:#{port}")
      options = http2 ? { protocol: ::Async::HTTP::Protocol::HTTP2 } : {}
      endpoint = ::Async::HTTP::Endpoint.new(uri, **options)
      [endpoint, endpoint]
    end
  end

  def free_port
    probe = ::TCPServer.new("127.0.0.1", 0)
    probe.addr[1]
  ensure
    probe&.close
  end

  def generate_certificate!
    key = ::OpenSSL::PKey::RSA.new(2048)
    cert = certificate_for(key)
    @key = key
    @certificate = cert
    @cert_store = ::OpenSSL::X509::Store.new
    @cert_store.add_cert(cert)
  end

  # A self-signed certificate for 127.0.0.1, valid from a minute ago for an hour.
  def certificate_for(key)
    name = ::OpenSSL::X509::Name.parse("/CN=127.0.0.1")
    cert = ::OpenSSL::X509::Certificate.new
    { version: 2, serial: ::OpenSSL::BN.rand(64), subject: name, issuer: name,
      public_key: key.public_key, not_before: ::Time.now - 60, not_after: ::Time.now + 3600, }
      .each { |attribute, value| cert.public_send(:"#{attribute}=", value) }
    cert.add_extension(subject_alt_name(cert))
    cert.sign(key, ::OpenSSL::Digest.new("SHA256"))
    cert
  end

  def subject_alt_name(cert)
    factory = ::OpenSSL::X509::ExtensionFactory.new
    factory.subject_certificate = cert
    factory.issuer_certificate = cert
    factory.create_extension("subjectAltName", "DNS:localhost,IP:127.0.0.1")
  end

  def server_ssl_context
    context = ::OpenSSL::SSL::SSLContext.new
    context.cert = @certificate
    context.key = @key
    context.alpn_select_cb = ->(protocols) { protocols.include?("h2") ? "h2" : protocols.first }
    context
  end

  # The client's context trusts the fixture's own certificate and offers h2 by ALPN, because a
  # caller-supplied context is used verbatim by the adapter and async-http alike.
  def client_ssl_context
    context = ::OpenSSL::SSL::SSLContext.new
    context.set_params(verify_mode: ::OpenSSL::SSL::VERIFY_PEER, cert_store: @cert_store)
    context.alpn_protocols = %w[h2 http/1.1]
    context
  end
end
