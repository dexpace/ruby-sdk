# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "socket"
require "dexpace"

# A deliberately small HTTP/1.1 client over a raw TCPSocket, written as a conforming transport
# with NAMED DEFECTS that can be switched on one at a time. It exists so the suite's own tests can
# prove each assertion in both directions -- it passes against the correct send and FAILS against
# the defect it was written to catch -- independently of any real adapter (8a's testing strategy,
# item 6: "a deliberately non-conforming fake transport ... proving the suite detects rather than
# merely runs"). The gem's own double, never a lift of dexpace-core's (design, "Work phase 8a
# postponed"). It is not an adapter: no pump, no proxy, no TLS, bodies read eagerly.
class RawWireTransport # rubocop:disable Metrics/ClassLength -- one client with twenty switchable defects; splitting it would hide which defect lives where
  DEFECTS = %i[
    form_type override_type ignore_body_type no_zero_length forward_host drop_pass_through
    skip_validation retry_once send_twice misclassify_cancel cancel_on_timeout non_retryable_timeout
    sticky_timeout ignore_window pretend_followed send_after_close cached_response leave_open
    short_read bare_errno
  ].freeze

  # The framing headers this client always recomputes and never copies (TRANSPORT-11).
  FRAMING = %w[content-length transfer-encoding].freeze

  # A non-retryable failure, for the defects that misclassify a timeout.
  class Bare < StandardError; end

  # One parsed response head and body, straight off the wire.
  Head = Struct.new(:code, :status_line, :headers, :body)

  attr_reader :calls

  def initialize(*defects, default_timeout: 1.5, owned: true)
    unknown = defects - DEFECTS
    raise ArgumentError, "unknown defects: #{unknown.inspect}" unless unknown.empty?

    @defects = defects
    @default_timeout = default_timeout
    @owned = owned
    @timeout_for = nil
    @cached = nil
    @closed = false
    @calls = 0
    @leaked = []
  end

  def defect?(name)
    @defects.include?(name)
  end

  def owned?
    @owned
  end

  def closed?
    @closed
  end

  def close
    @closed = true
    @leaked.each { |socket| socket.close unless socket.closed? }
    @leaked.clear
    nil
  end

  def call(request, options, cancellation)
    raise Dexpace::ClosedError, "closed" if @closed && !defect?(:send_after_close)

    @calls += 1
    return build_response(request, @cached) if defect?(:cached_response) && @cached

    validate!(request) unless defect?(:skip_validation)
    bytes = wire_bytes(request)
    response = exchange(request, bytes, timeout_for(options), cancellation)
    response = exchange(request, bytes, timeout_for(options), cancellation) if defect?(:send_twice)
    response
  end

  private

  def timeout_for(options)
    chosen = options.timeout || @default_timeout
    return chosen unless defect?(:sticky_timeout)

    @timeout_for ||= chosen
  end

  def validate!(request)
    request.headers.each_entry do |name, value|
      Dexpace::HeaderSyntax.validate_name!(name)
      Dexpace::HeaderSyntax.validate_outbound_value!(value, name: name)
    end
  end

  # The request head and body as bytes, under this double's header policy.
  def wire_bytes(request)
    body = body_bytes(request)
    lines = request_line(request)
    lines.concat(header_lines(request, body))
    lines << "Content-Length: #{body.bytesize}" if body && !defect?(:no_zero_length)
    "#{lines.join("\r\n")}\r\n\r\n".b + (body || "").b
  end

  def request_line(request)
    url = request.url
    lines = ["#{request.method.token} #{url.request_uri} HTTP/1.1"]
    lines << "Host: #{url.hostname}:#{url.port}" unless defect?(:forward_host)
    lines
  end

  def header_lines(request, body)
    lines = []
    explicit_type = nil
    request.headers.each_entry do |name, value|
      folded = name.downcase
      next unless copied?(folded)

      explicit_type = value if folded == "content-type"
      lines << "#{name}: #{value}" unless folded == "content-type" && defect?(:override_type)
    end
    type = content_type(request, body, explicit_type)
    lines << "Content-Type: #{type}" if type
    lines
  end

  # Whether a caller's header is copied onto the wire: framing is recomputed, Host is this
  # client's own unless the defect forwards it, and everything else is pass-through unless the
  # defect drops it.
  def copied?(folded)
    return false if FRAMING.include?(folded)
    return defect?(:forward_host) if folded == "host"

    folded == "content-type" || !defect?(:drop_pass_through)
  end

  def content_type(request, body, explicit_type)
    return nil if body.nil? || (explicit_type && !defect?(:override_type))

    media = request.body&.media_type
    return media.render if media && !defect?(:ignore_body_type)

    form_type_default
  end

  def form_type_default
    defect?(:form_type) ? "application/x-www-form-urlencoded" : nil
  end

  # The body, pulled exactly once through #each; nil for a body-forbidden method, and a
  # zero-length one for a body-less permitted method (TRANSPORT-26).
  def body_bytes(request)
    body = request.body
    if body.nil?
      return nil if request.method.body_forbidden? || defect?(:no_zero_length)

      return (+"").b
    end
    return File.binread(body.path) if defect?(:ignore_window) && body.respond_to?(:path)

    bytes = (+"").b
    body.each { |chunk| bytes << chunk }
    bytes
  end

  def exchange(request, bytes, timeout, cancellation)
    attempt(request, bytes, timeout, cancellation)
  rescue Dexpace::TransportError
    raise unless defect?(:retry_once) && (@retried = !@retried)

    attempt(request, bytes, timeout, cancellation)
  end

  def attempt(request, bytes, timeout, cancellation)
    socket = connect(request)
    subscription = cancellation.on_cancel { socket.close }
    begin
      socket.write(bytes)
      read_response(request, socket, timeout, cancellation)
    rescue IOError, SystemCallError => error
      raise classify(error, cancellation)
    ensure
      subscription.detach
      # The leave_open defect must keep the socket REFERENCED, not merely unclosed: an unreferenced
      # TCPSocket is closed by its finalizer at the next GC, and under the whole-repository
      # `test:gems` process one ran inside the release assertion's bounded wait, so the server saw
      # the close and the defect passed the assertion it exists to fail. The transport's own
      # #close releases them, which the case teardown reaches after the assertion has judged.
      if defect?(:leave_open)
        @leaked << socket
      elsif !socket.closed?
        socket.close
      end
    end
  end

  def connect(request)
    TCPSocket.new(request.url.hostname, request.url.port)
  rescue SystemCallError => error
    raise error if defect?(:bare_errno)

    raise Dexpace::TransportError.new("connect failed: #{error.message}", phase: :connect)
  end

  def classify(error, cancellation)
    if cancellation.cancelled?
      return Dexpace::TransportError.new("cancelled", phase: :read) if defect?(:misclassify_cancel)

      return Dexpace::CancelledError.new(cancellation.reason)
    end
    Dexpace::TransportError.new(error.message, phase: :read)
  end

  def read_response(request, socket, timeout, cancellation)
    raise timeout_error(cancellation) if socket.wait_readable(timeout).nil?

    head = read_head(socket)
    return pretend_followed(request) if head.code / 100 == 3 && defect?(:pretend_followed)

    # The cached defect keeps the WIRE bytes and rebuilds a fresh response from them per call, so
    # every later call answers with the first exchange's status and body.
    @cached = head if defect?(:cached_response)
    build_response(request, head)
  end

  def read_head(socket)
    status_line = socket.gets
    if status_line.nil?
      raise Dexpace::TransportError.new("the connection closed before a status line", phase: :read)
    end

    headers = read_headers(socket)
    Head.new(status_line.split[1].to_i, status_line, headers, read_body(socket, headers))
  end

  def timeout_error(cancellation)
    if defect?(:cancel_on_timeout)
      return Dexpace::CancelledError.new(cancellation.reason || :timeout)
    end
    return Bare.new("timed out") if defect?(:non_retryable_timeout)

    Dexpace::TransportError.new("timed out", phase: :read)
  end

  def read_headers(socket)
    builder = Dexpace::Headers.inbound_builder
    while (line = socket.gets) && line != "\r\n"
      name, value = line.chomp.split(":", 2)
      next unless Dexpace::HeaderSyntax.valid_name?(name.to_s) &&
                  Dexpace::HeaderSyntax.valid_inbound_value?(value.to_s.strip)

      builder.add(name, value.strip)
    end
    builder.build
  end

  def read_body(socket, headers)
    length = headers["Content-Length"]&.first&.to_i
    length /= 2 if length && defect?(:short_read)
    (length ? socket.read(length) : socket.read).to_s.b
  end

  def build_response(request, head)
    body = Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(head.body),
                                     media_type: media_type(head.headers),
                                     content_length: head.body.bytesize,)
    Dexpace::Response.build(request: request, protocol: "HTTP/1.1", status: head.code,
                            reason: head.status_line.split(" ", 3)[2]&.strip,
                            headers: head.headers, body: body,)
  end

  def media_type(headers)
    raw = headers["Content-Type"]&.first
    raw && Dexpace::MediaType.parse(raw)
  rescue Dexpace::InvalidArgumentError
    nil
  end

  def pretend_followed(request)
    Dexpace::Response.build(request: request, protocol: "HTTP/1.1", status: 200, reason: "OK",
                            headers: Dexpace::Headers::EMPTY_INBOUND, body: nil,)
  end
end
