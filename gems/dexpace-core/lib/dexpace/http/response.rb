# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "headers"
require_relative "protocol"
require_relative "request"
require_relative "status"

module Dexpace
  # An HTTP response: the originating request, the negotiated protocol, the status, an optional
  # reason phrase, headers and an optional body (HTTP-6).
  #
  # `body` is a Dexpace::Body or nil (P3-15). #close, #body_string and #body_bytes -- HTTP-43,
  # HTTP-42 and HTTP-41/BODY-16 -- are phase 3b's, and all three are written against exactly two
  # members of whatever the body slot holds, #source and #close, which Dexpace::Body declares for
  # every body (P3-23). The builder coerces nothing: a String in the slot is a caller mistake that
  # #body_string reports by name, not a BytesBody.
  class Response < Data.define(:request, :protocol, :status, :reason, :headers, :body)
    include Model

    private_class_method :new

    # The validating factory every construction path goes through.
    def self.build(request:, protocol:, status:, headers:, reason: nil, body: nil)
      new(
        request: request, protocol: protocol, status: status, reason: reason, headers: headers,
        body: body,
      )
    end

    # A builder with nothing set.
    def self.builder
      Builder.new
    end

    # The required members are checked in the order HTTP-4 lists them, so a missing one fails
    # with `status is required` and names the field whether it was reached through `.build`,
    # through #with or through the builder. Protocol and status are coerced through their own
    # factories rather than trusted, as Request does with its method and URL; both factories are
    # idempotent on their own type so a builder pays nothing for it.
    #
    # The reason phrase is the one caller-supplied String this model carries, so it is copied and
    # frozen here (XCUT-15): stored as given, a later mutation of the caller's String would change
    # the model in place, and the model would not be Ractor-shareable either.
    def initialize(request:, protocol:, status:, reason:, headers:, body:)
      unless Model.required!("request", request).is_a?(Request)
        raise InvalidArgumentError, "request must be a Dexpace::Request"
      end

      negotiated = Protocol.parse(Model.required!("protocol", protocol))
      code = Status.of(Model.required!("status", status))
      unless Model.required!("headers", headers).is_a?(Headers)
        raise InvalidArgumentError, "headers must be a Dexpace::Headers"
      end
      unless reason.nil? || reason.is_a?(String)
        raise InvalidArgumentError, "reason must be a String"
      end

      super(request: request, protocol: negotiated, status: code,
            reason: reason.nil? ? nil : Model.frozen_string(reason), headers: headers, body: body)
    end

    # HTTP-3: a builder pre-filled from this instance.
    def new_builder
      Builder.new(
        request: request, protocol: protocol, status: status, reason: reason, headers: headers,
        body: body,
      )
    end

    # HTTP-11's "a response MUST expose these derived from its status": six delegations, not a
    # second copy of the ranges.
    def informational? = status.informational?
    # 200-299, delegated (HTTP-11).
    def success? = status.success?
    # 300-399, delegated (HTTP-11).
    def redirect? = status.redirect?
    # 400-499, delegated (HTTP-11).
    def client_error? = status.client_error?
    # 500-599, delegated (HTTP-11).
    def server_error? = status.server_error?
    # 400-599, delegated (HTTP-11).
    def error? = status.error?

    # HTTP-43: closeable, idempotent, forwarding to the body. A pure forward and nothing else --
    # a Data instance is frozen and cannot hold a latch, which would matter if HTTP-43 needed one.
    # It does not: its own appendix-C text says "(Idempotency is delegated to the body's
    # idempotent close per HTTP-41; a bodyless response close is a no-op.)" So idempotence lives
    # in ResponseBody's Closeable latch, which is where HTTP-41 puts it.
    def close
      body&.close
      nil
    end

    # HTTP-42, and the ONE decode boundary in this SDK. Three steps, and all three are
    # load-bearing: design §3.1's own recipe is wrong, see
    # `docs/knowledge/notes/io-and-byte-streams.md`.
    #
    # 1. Resolve the charset from the body's media type. MediaType#charset already returns nil
    #    for an ABSENT or an UNKNOWN-to-this-Ruby charset, so Encoding.find cannot raise and
    #    HTTP-42's UTF-8 fallback needs no second validation.
    # 2. RETAG the drained BINARY bytes to that encoding, which is 3a's #read_string. Skipping
    #    this mangles the payload: from BINARY every byte >= 0x80 is undefined in the SOURCE
    #    encoding, so "café".b.encode(UTF_8, invalid: :replace, undef: :replace) is "caf" plus
    #    TWO replacement characters, on 3.2.11, 3.4.10 and 4.0.6 alike.
    # 3. Transcode with BOTH encodings named. #encode with no target converts to
    #    Encoding.default_internal, a process global the host sets -- the same
    #    passes-where-you-look hazard design §3.5 pins URI::RFC3986_PARSER against.
    #
    # BODY-16: the body is closed in an ensure whether or not the read succeeded, and so is the
    # handle #source handed out (#read_through, below).
    def body_string
      current = body
      return nil if current.nil?

      encoding = self.class.resolve_charset(current.media_type)
      read_through(current) do |source|
        source.read_string(encoding).encode(encoding, invalid: :replace, undef: :replace)
      end
    end

    # HTTP-41/BODY-16's byte-array sibling. It decodes NOTHING and returns BINARY; the same
    # finally-style close applies.
    def body_bytes
      current = body
      return nil if current.nil?

      read_through(current) { |source| source.read || (+"").b }
    end

    # HTTP-42's charset resolution: the declared charset when this Ruby knows it, UTF-8 otherwise.
    # MediaType#charset only ever names an encoding this Ruby has, so the second fallback is
    # unreachable; it is there because rbs declares Encoding.find as nullable.
    def self.resolve_charset(media_type)
      name = media_type&.charset
      return ::Encoding::UTF_8 if name.nil?

      ::Encoding.find(name) || ::Encoding::UTF_8
    end

    private

    # The one read path both readers share, and the second half of BODY-16's finally-close: the
    # handle #source returned is closed FIRST, then the body, each in its own ensure so the second
    # close runs whatever the first did.
    #
    # Closing the handle is not redundant with closing the body. For a ResponseBody the two are the
    # same idempotent stream close (BODY-15), but for a BufferBody and for a fits-cap
    # ResponseLoggingBody the handle is a fresh #peek VIEW of a buffer that outlives this call, and
    # neither body's #close reaches it -- BufferBody#close is the contract's no-op and the wrapper's
    # close is its delegate's -- so a reader that dropped it would leave one registered view in
    # that buffer per call, which is the Array#delete growth Task 13 measured (design §7.1 applied,
    # rule 4: "every view core takes, core closes"; review round 0, R0-1). For the over-cap
    # composite the handle's close is the Tail's, which deregisters its prefix view and routes to
    # the wrapper's one guard (BODY-27). `respond_to?` rather than an unconditional call, as the
    # bodies' own #release methods do: a source is checked as a duck, never with is_a?, and
    # Dexpace::IO::_Source declares no #close.
    def read_through(body)
      source = body.source
      begin
        yield source
      ensure
        source.close if source.respond_to?(:close)
      end
    ensure
      body.close
    end
  end
end
