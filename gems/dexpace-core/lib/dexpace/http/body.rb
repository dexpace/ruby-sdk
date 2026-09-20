# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../io"
require_relative "../io/buffer"
require_relative "../error/stream_error"
require_relative "../error/invalid_argument_error"
require_relative "../model"
require_relative "media_type"

module Dexpace
  # The request/response body contract, the factory home, and the two copy routines every variant
  # shares (HTTP-36, HTTP-38, BODY-1, BODY-35).
  #
  # A module and not a base class: MultipartBody and ResponseLoggingBody each compose with
  # something else (Closeable, and later a codec's own mixin), and Ruby has single inheritance. A
  # module and not an RBS interface: an interface can be the type sig/ narrows Request#body and
  # Response#body to (P3-15), but it cannot carry the default #replayable?, #content_length and
  # #each implementations, and restating those in eleven classes is the drift this exists to stop.
  #
  # Public, not private_constant, for TypedReads' reason (P3-8): the runtime surface snapshot walks
  # each class's public_instance_methods(false), which does not see a method reaching a class
  # through an included module, so a private module would hide most of phase 3b from the gate that
  # exists to see it.
  #
  # One hook: #write_to(sink) -> Integer. Everything else derives from it.
  #
  # BODY-4's three declines are NOT unified here. This module ships one #replayable? property; the
  # retry path stops and surfaces the last outcome, the auth path returns the original challenge
  # response unchanged and does NOT close it, and the redirect path raises. All three are phase 6's,
  # in three places, because BODY-4 says a port need not unify them.
  module Body # rubocop:disable Metrics/ModuleLength -- the whole body contract and its factory home by design; see above
    # #each's destination: a sink-shaped object that hands each write to a block. Private, so no
    # constant enters the NFR-4 surface.
    class BlockSink
      def initialize(&block)
        @block = block
      end

      # The chunk handed to the block is an INDEPENDENT frozen BINARY String, by 3a's own
      # binary_of/store_append rule, and that is not tidiness. FileBody#write_to is
      # ::IO.copy_stream, which REUSES AND CLEARS one destination String across #write calls, so
      # yielding the argument itself hands a consumer a buffer that is empty the moment the block
      # returns: `file_body.each.to_a` comes back as N zero-length Strings, all the same object
      # (verified on 3.2.11, 3.4.10 and 4.0.6). Every other variant reaches a sink through
      # #emit_exactly, which already copies; FileBody -- and any MultipartBody or
      # RequestLoggingBody carrying a file part -- is the one path that does not, and §10.2's #each
      # duck type is public surface.
      def write(*strings)
        payload = strings.length == 1 ? strings.first : strings.join
        chunk =
          if payload.frozen? && payload.encoding == ::Encoding::BINARY
            payload
          else
            payload.b.freeze
          end
        @block.call(chunk)
        chunk.bytesize
      end
    end

    # HTTP-51's declared-length half: the same framing routine run against this counts bytes
    # instead of writing them, so a declared length cannot drift from the bytes written.
    class CountingSink
      attr_reader :bytesize

      def initialize
        @bytesize = 0
      end

      # Counts what a real sink would have taken, so the framing routine needs no second mode.
      def write(*strings)
        added = strings.sum(&:bytesize)
        @bytesize += added
        added
      end
    end

    private_constant :BlockSink, :CountingSink

    # ---- the contract ----------------------------------------------------------------------

    # HTTP-36's single write-to-sink operation, and the only byte-producing primitive a body has.
    # `sink` is anything responding to #write (Dexpace::IO::_Sink): a TeeSink, a BufferedSink, a
    # Buffer, a raw ::IO, the transport's own sink. Returns the byte count written.
    def write_to(_sink)
      raise ::NotImplementedError,
            "#{self.class} includes Dexpace::Body and must define #write_to(sink)"
    end

    # HTTP-36: nullable.
    def media_type
      nil
    end

    # HTTP-36/BODY-35: the exact count when known, and the -1 sentinel when not. Never nil --
    # BODY-35 fixes the sentinel in normative text and an ID-bearing rule beats the styleguide's
    # nil-as-absence default.
    def content_length
      -1
    end

    # BODY-1: false by default. True only where writing more than once yields byte-for-byte
    # identical output, which is a property a variant earns rather than one a caller may assert.
    def replayable?
      false
    end

    # The READ side of the contract, and the counterpart to #write_to (P3-23).
    # Response#close, #body_string and #body_bytes are written against #source and #close, so a
    # body that can occupy Response#body and answers neither is a NoMethodError one layer up --
    # which is exactly what BODY-30/HTTP-52's BufferBody was.
    #
    # The default RAISES rather than being absent, and that is what makes the sig/ declaration true
    # of every Dexpace::Body: P3-15 narrows Response#body to Dexpace::Body?, and
    # Response#body_string reads through this, so a declared-but-undefined member would make the
    # signature a lie. The three bodies that can occupy Response#body -- ResponseBody,
    # ResponseLoggingBody and BufferBody -- override it with the handle they already hold; the
    # seven request-body variants raise from here, which is a named failure and not a
    # NoMethodError.
    def source
      raise Dexpace::StreamError,
            "#{self.class} is a request body and exposes no readable source; #write_to is its " \
            "one byte-producing operation (HTTP-36)"
    end

    # HTTP-43 forwards a response's close to its body, and a body that owns no transport resource
    # has nothing to release. BODY-30 requires exactly that of the buffered error copy: the
    # ensure-close inside Response#body_string must leave a BufferBody "readable independently and
    # repeatably". Dexpace::ResponseBody and Dexpace::ResponseLoggingBody include
    # Dexpace::Closeable AFTER this module, so their latch wins where a close does release
    # something.
    def close
      nil
    end

    # HTTP-46's body half: phase 1's Request#== compares bodies by value and Request#hash folds
    # the body in, so every body answers all three together. The module's default is IDENTITY,
    # which is the correct value comparison for every variant that holds a live stream or an
    # #each-shaped object -- StreamBody, ChunkedBody, ResponseBody, ResponseLoggingBody -- because
    # two different open streams are two different values. The variants whose bytes are fixed at
    # construction override all three over the facts that fix them.
    def ==(other)
      equal?(other)
    end
    alias eql? ==

    # Agrees with #==.
    def hash
      object_id.hash
    end

    # BODY-3/HTTP-37: self when already replayable, otherwise drain once into memory and hand back
    # a replayable buffer-backed body, leaving the original consumed.
    def to_replayable
      return self if replayable?

      buffer = Dexpace::IO::Buffer.new
      write_to(buffer)
      Dexpace::BufferBody.new(buffer, media_type: media_type)
    end

    # Design §10.2: every body is also a canonical body representation, so a transport can iterate
    # it. Derived from #write_to once, here, so BODY-17's "the exact bytes the wrapped body's single
    # write produces" cannot mean two different things on the two paths (P3-21).
    #
    # §7.1's residue, widened by `docs/knowledge/notes/pagination.md`: an ordinary #each method
    # leaks exactly like an Enumerator.new block. A consumer that drives to_enum(:each) with #next
    # and abandons it does not run this method's ensures -- #rewind does not run them either, and
    # block_given? is true under that drive so no in-method guard helps. Bodies that hold a resource
    # therefore hold it on the object and expose #close; FileBody, which BODY-11 obliges to open a
    # fresh handle per write, cannot, and states the residue in its own YARD.
    def each(&block)
      return to_enum(:each) if block.nil?

      write_to(BlockSink.new(&block))
      nil
    end

    # ---- the factories (HTTP-38/BODY-35, one place) ----------------------------------------

    # Replayable: an independent frozen BINARY copy.
    def self.bytes(bytes, media_type: nil)
      Dexpace::BytesBody.new(bytes, media_type: media_type)
    end

    # Replayable. The String is encoded EAGERLY, at construction, so #content_length is exact and a
    # later mutation of the caller's String cannot change the body -- 3a's .of_bytes independent
    # copy property, applied to text (plan decision 3).
    def self.string(text, media_type: nil, encoding: ::Encoding::UTF_8)
      unless text.is_a?(::String)
        raise Dexpace::InvalidArgumentError, "string takes a String, got #{text.class}"
      end

      Dexpace::BytesBody.new(text.encode(encoding).b, media_type: media_type)
    end

    # Replayable: a fresh handle per write (HTTP-40/BODY-11).
    def self.file(path, media_type: nil, offset: 0, count: nil)
      Dexpace::FileBody.new(path, media_type: media_type, offset: offset, count: count)
    end

    # Single-use unless the stream is seekable, the length is known and fits the ceiling, and
    # ownership was not transferred (BODY-9, R9).
    def self.stream(io, media_type: nil, content_length: -1, close: false)
      Dexpace::StreamBody.new(
        io, media_type: media_type, content_length: content_length, close: close,
      )
    end

    # Unconditionally single-use, and no `replayable:` keyword (P3-19).
    def self.chunked(chunked, media_type: nil, content_length: -1)
      Dexpace::ChunkedBody.new(chunked, media_type: media_type, content_length: content_length)
    end

    # Replayable, application/x-www-form-urlencoded, "+" for space.
    def self.form(pairs)
      Dexpace::FormBody.new(pairs)
    end

    # Replayable if and only if every part is (BODY-2).
    def self.multipart(parts, boundary: nil, subtype: "form-data")
      Dexpace::MultipartBody.new(parts, boundary: boundary, subtype: subtype)
    end

    # Replayable: a body over a Dexpace::IO::Buffer core owns, read through fresh views.
    def self.buffer(buffer, media_type: nil)
      Dexpace::BufferBody.new(buffer, media_type: media_type)
    end

    # SERDE-2's factory, the ninth beside phase 3b's eight (phase 7a): a value plus a serde,
    # with the serde's declared media type as the body's -- "that media type MUST be used as the
    # default Content-Type when a request body is created from a value plus a Serde". Returns a
    # replayable BytesBody over `serde.dump_bytes(value)`, so the body knows its exact length and
    # is retryable with #to_replayable doing nothing (BODY-1, HTTP-38).
    #
    # The seam's `#media_type` answers a Dexpace::MediaType or a String (`_Codec`, settled by
    # phase 7a): a MediaType passes through and a String is parsed through phase 1's
    # MediaType.parse, which runs the outbound header-value grammar first, so a codec answering
    # a value a Content-Type header could not carry is refused there, naming the value. A nil or
    # empty media type raises naming the codec's class: SERDE-2's "MUST NOT be defaulted to a
    # format-agnostic constant at the SPI level" means there is no fallback to fall back to --
    # phase 2 enforces the presence at .conforms?, and this is the same rule at the one call site
    # that consumes the value.
    #
    # @param value [Object] anything the serde can encode
    # @param serde [Dexpace::_Codec] the serde, `#dump_bytes` and `#media_type` at least
    # @return [Dexpace::BytesBody]
    # @raise [Dexpace::InvalidArgumentError] on a nil serde ("serde is required"), one answering
    #   neither seam method, or a nil, empty or unparseable media type
    # @raise [Dexpace::Serde::SerializationError] from the serde, on an unencodable value
    def self.serialized(value, serde:)
      Dexpace::Model.required!("serde", serde)
      unless serde.respond_to?(:dump_bytes) && serde.respond_to?(:media_type)
        raise Dexpace::InvalidArgumentError,
              "serde must answer #dump_bytes and #media_type (the codec seam), got #{serde.class}"
      end

      declared = serde.media_type
      # SERDE-2: no format-agnostic default, so a codec that declares nothing is a caller mistake.
      if declared.nil? || (declared.respond_to?(:empty?) && declared.empty?)
        raise Dexpace::InvalidArgumentError, "#{serde.class} declared no media type (SERDE-2)"
      end

      media_type = declared.is_a?(Dexpace::MediaType) ? declared : Dexpace::MediaType.parse(declared)
      bytes(serde.dump_bytes(value), media_type: media_type)
    end

    # ---- BODY-32's cap rules, shared by every capped operation --------------------------

    # BODY-32: reject a negative cap, silently clamp down to the ceiling, never up. Float::INFINITY
    # is accepted and clamps to the ceiling; [Float::INFINITY, Integer].min is an Integer. The
    # ceiling is the CONFIGURED one (phase 5a): Dexpace::IO.max_materialized_bytes, read per call.
    def self.clamp_cap(cap)
      ceiling = Dexpace::IO.max_materialized_bytes
      return ceiling if cap.equal?(::Float::INFINITY)

      unless cap.is_a?(::Integer)
        raise Dexpace::InvalidArgumentError,
              "cap must be an Integer or Float::INFINITY, got #{cap.class}"
      end
      raise Dexpace::InvalidArgumentError, "cap must not be negative, got #{cap}" if cap.negative?

      [cap, ceiling].min
    end

    private_class_method :clamp_cap

    # BODY-30/HTTP-52 fix this number in their own text ("a fixed cap (1 MiB)"), so there is nothing
    # to configure and it takes no keyword. Distinct from Dexpace::IO::MAX_MATERIALIZED_BYTES, which
    # bounds one contiguous String, and from the body-logging preview size, which IS a parameter
    # (its source is phase 5b's, Tasks 14-15). Collapsing any two of the three breaks a requirement
    # (R5). Design §5.1 placed the constant in phase 4's Recovery.buffer_error_body; it lives one
    # layer down because the operation that reads it is a body operation and 3b ships that first
    # (addendum B2), and phase 4's step reads this one rather than declaring a second.
    MAX_BUFFERED_ERROR_BODY_BYTES = 1024 * 1024

    # ---- BODY-30/HTTP-52's bounded replayable copy -----------------------------------------

    # Drains at most `cap` bytes of `body` into a Dexpace::IO::Buffer, STOPS reading rather than
    # reading and discarding, and returns a replayable buffer-backed body that is readable
    # independently and repeatably after the transport connection is released.
    #
    # DELIBERATELY STATUS-BLIND. It never reads a status, which is what makes BODY-31 ("mapping
    # applies only to 4xx/5xx") impossible to get wrong from inside the body layer: the only thing
    # that can classify is phase 4's recovery step, and the only predicate it may use is phase 1's
    # Dexpace::Status#error?. "A response with no body is returned unchanged" is a statement about a
    # RESPONSE and is phase 4's too.
    #
    # BODY-30's close clause: the drain runs inside the original body's close-guaranteeing scope, so
    # a buffer-allocation failure still releases the connection. The close is unguarded, because
    # #close is on the contract (P3-23).
    def self.buffer_bounded(body, cap: MAX_BUFFERED_ERROR_BODY_BYTES)
      limit = clamp_cap(cap)
      buffer = Dexpace::IO::Buffer.new
      begin
        copy_bounded(body, buffer, limit)
      ensure
        body.close
      end
      Dexpace::BufferBody.new(buffer, media_type: body.media_type)
    end

    # Truncation is MARKERLESS -- no ellipsis, no sentinel -- and the bytes beyond the cap are not
    # pulled from the body at all: the loop stops asking rather than reading and discarding.
    #
    # It drains through the READ side of the contract -- #source (P3-23) -- and NOT through #each,
    # which is #write_to (P3-21). BODY-30/HTTP-52 are about an error RESPONSE body, and all three
    # bodies that can occupy Response#body answer #source, while ResponseLoggingBody's #write_to
    # RAISES by design ("a response capture wrapper produces no request body"). Phase 5b's logging
    # step puts exactly that wrapper into Response#body at Stages::LOGGING, which PIPE-2 places
    # INSIDE the RETRY pillar, so phase 6a's per-attempt Recovery.buffer_error_body and phase 4b's
    # error-mapping step both hand one to this routine on any 4xx/5xx. Draining through #each would
    # raise there instead of buffering -- RECOV-16, RETRY-36, BODY-30 and HTTP-52 all lost at once.
    # Found by review on 2026-09-13; it is the write-side half of the surface P3-23 records.
    #
    # The original's close still happens in .buffer_bounded's ensure above, so a FileBody handle or
    # a transport connection is released on every path. The handle #source returned is closed
    # here, before that, in its own ensure: for a BufferBody or a fits-cap ResponseLoggingBody it
    # is a fresh #peek view of a buffer that outlives this call and neither body's #close reaches
    # (design §7.1 applied, rule 4: every view core takes, core closes; review round 0, R0-1); for
    # a ResponseBody it is the same idempotent stream close the body's own performs. Guarded with
    # `respond_to?` because the read side's contract on a source is Dexpace::IO::_Source's
    # #read_into alone, which declares no #close.
    def self.copy_bounded(body, buffer, limit)
      return nil if limit.zero?

      source = body.source
      begin
        taken = 0
        while taken < limit
          chunk = (+"").b
          got = source.read_into(chunk, count: limit - taken)
          break if got.negative?

          buffer.write(chunk)
          taken += got
        end
      ensure
        source.close if source.respond_to?(:close)
      end
      nil
    end

    private_class_method :copy_bounded

    private

    # HTTP-51's counting half. Private, so the constant stays off the NFR-4 surface and the
    # runtime snapshot's constant walk never sees it.
    def counting_sink
      CountingSink.new
    end

    # HTTP-39/BODY-10, BODY-13 and BODY-25 in one routine: exactly `count` bytes from a
    # Dexpace::IO::_Source into `sink`, a premature end naming delivered-of-total, a zero-length
    # read for a positive request as a stream-contract violation rather than an EOF or a spin, and
    # a declared length of 0 as a legitimate empty write.
    #
    # It is this rather than 3a's TypedWrites#write_all(source) (P3-20): #write_all is a method on a
    # SINK, so using it would mean wrapping the transport's #write-shaped destination in a
    # BufferedSink -- which IO-6 then obliges to close the socket, exactly what a body must never do
    # (BODY-8, §10.12), and 3a ships no borrowing variant by design.
    #
    # The chunk size is whatever the source's own read returned: #read_into is asked for the
    # whole remaining count and delivers what it has, so BODY-17's byte-exact mirroring sees the
    # upstream's own boundaries rather than a size this layer invented (plan decision 4).
    def copy_exactly(source, sink, count)
      transferred = 0
      while transferred < count
        wanted = count - transferred
        chunk = (+"").b
        taken = source.read_into(chunk, count: wanted)
        if taken.negative?
          raise Dexpace::StreamError.short_transfer(transferred: transferred, expected: count)
        end
        raise Dexpace::StreamError.zero_read(requested: wanted) if taken.zero?

        emit_exactly(sink, chunk)
        transferred += taken
      end
      transferred
    end

    # The other direction, and the second half of BODY-13's short-write detection: one String to a
    # #write-shaped sink, retagged to BINARY on the way (a body may yield a frozen non-BINARY chunk;
    # String#b is the retag because force_encoding raises FrozenError on a frozen String even when
    # the target encoding is already its own). Both routines raise through 3a's
    # StreamError.short_transfer, so BODY-13's one-message-form rule holds across the two.
    def emit_exactly(sink, string)
      payload = string.frozen? && string.encoding == ::Encoding::BINARY ? string : string.b
      return 0 if payload.empty?

      written = sink.write(payload)
      if written.is_a?(::Integer) && written < payload.bytesize
        raise Dexpace::StreamError.short_transfer(transferred: written, expected: payload.bytesize)
      end

      payload.bytesize
    end

    # BODY-6/BODY-7 and BODY-9's race-safe rewind use the same shape, and it is the only
    # synchronised state a request body has: a Thread::Mutex held across the flag flip and across
    # nothing else. Ruby's Mutex is non-reentrant and per-fiber-owned, so holding it across the
    # write deadlocks two fibers of one thread.
    def initialize_single_use
      @dexpace_body_mutex = ::Thread::Mutex.new
      @dexpace_consumed = false
      @dexpace_writing = false
      nil
    end

    # BODY-6: a second write raises rather than silently emitting zero bytes.
    # BODY-7: under concurrent writes exactly one passes and every loser sees the same failure.
    def claim_single_use!
      first = @dexpace_body_mutex.synchronize do
        if @dexpace_consumed
          false
        else
          @dexpace_consumed = true
        end
      end
      return nil if first

      raise Dexpace::StreamError,
            "#{self.class} is single-use and its bytes have already been written (BODY-6)"
    end

    # BODY-9: "the rewind MUST be race-safe (at most one reset between any two writes)". A second
    # concurrent write observes the flag and raises rather than issuing a second seek underneath
    # the first write's read.
    def claim_replay!
      mine = @dexpace_body_mutex.synchronize do
        if @dexpace_writing
          false
        else
          @dexpace_writing = true
        end
      end
      return nil if mine

      raise Dexpace::StreamError,
            "a write is already in progress on this #{self.class}; BODY-9 permits at most one " \
            "reset between any two writes"
    end

    def release_replay!
      @dexpace_body_mutex.synchronize { @dexpace_writing = false }
      nil
    end
  end
end
