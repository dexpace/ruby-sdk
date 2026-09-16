# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../../io/buffered_source"

module Dexpace
  # A body over a caller-supplied stream: HTTP-38/BODY-35's one-shot source, BODY-6..BODY-9.
  #
  # OWNERSHIP (BODY-8, design §10.12). A body closes exactly the sources it opened. This one opened
  # nothing, so it closes NOTHING unless the caller transferred ownership explicitly at the factory
  # with `close: true` -- at which point BODY-8's MUST applies and the single write drains and
  # closes, so skipping materialisation does not leak the stream.
  #
  # `close: true` also forces single-use, and that is BODY-8's own sentence rather than an extra
  # rule: "the rewindable variant must keep it open to replay". A body that closes its stream as
  # part of its one write cannot rewind it for a second (plan decision 6).
  class StreamBody
    include Dexpace::Body

    attr_reader :media_type, :content_length

    def initialize(io, media_type: nil, content_length: -1, close: false)
      unless io.respond_to?(:readpartial) || io.respond_to?(:read)
        raise Dexpace::InvalidArgumentError,
              "a stream body's io must respond to #readpartial or #read, got #{io.class}"
      end
      unless content_length.is_a?(::Integer) && content_length >= -1
        raise Dexpace::InvalidArgumentError,
              "content_length must be an Integer of -1 or more, got #{content_length.inspect}"
      end

      @io = io
      @media_type = media_type
      @content_length = content_length
      @close = close ? true : false
      @origin, @rewindable = probe_rewindability(io)
      initialize_single_use
    end

    # BODY-9, all three conditions, plus BODY-8's ownership exclusion. The stream must be seekable
    # (probed once at construction), the length must be KNOWN -- BODY-9 says "of known length"
    # literally -- and it must fit the platform's maximum single-array bound, which design §10.18
    # substitutes as Dexpace::IO::MAX_MATERIALIZED_BYTES and IO-9 and BODY-32 share. Otherwise
    # single-use, which is BODY-9's own "otherwise it MUST be single-use".
    def replayable?
      @rewindable && !@close && @content_length != -1 &&
        @content_length <= Dexpace::IO::MAX_MATERIALIZED_BYTES
    end

    # The position the body starts at, captured by the same probe that proved it can return there.
    # Replay rewinds HERE and not to byte 0: a caller who hands over a File already positioned at
    # 4096 means the body starts at 4096, and a rewind to 0 would silently send bytes the caller
    # never offered (P3-16).
    attr_reader :origin

    # The probe's answer, observable so a test can tell "the probe said no" from "BODY-8's
    # ownership forbids replay".
    def rewindable?
      @rewindable
    end

    # Whether `close: true` transferred the stream's close to this body.
    def owns_stream?
      @close
    end

    # The replayable path rewinds under BODY-9's guard; the single-use path claims BODY-6's latch
    # and closes the stream afterwards only when this body owns it.
    def write_to(sink)
      replayable? ? write_replayable(sink) : write_once(sink)
    end

    # HTTP-46 is Dexpace::Body's identity default: two different open streams are two different
    # values, and nothing about a live stream makes two of them interchangeable.

    private

    # BODY-9's "supports mark/reset", given a Ruby subject (R9, P3-16). respond_to?(:rewind) is
    # true for a pipe, a socket, a StringIO and a File alike, so it discriminates nothing; a trial
    # #rewind discriminates but silently moves a caller's mid-file cursor to 0. `pos` then
    # `seek(pos)` does both jobs: it raises Errno::ESPIPE on a pipe or a socket even at position 0
    # with nothing consumed, and it is a genuine no-op on a seekable stream at any position.
    # Errno::ESPIPE is a SystemCallError and NOT an IOError, so a bare `rescue IOError` would not
    # catch it. Guarded by respond_to? on both methods first, because the factory accepts any
    # #read-shaped object and a bare probe would raise NoMethodError out of a question.
    def probe_rewindability(io)
      return [0, false] unless io.respond_to?(:pos) && io.respond_to?(:seek)

      origin = io.pos
      io.seek(origin, ::IO::SEEK_SET)
      [origin, true]
    rescue ::SystemCallError
      [0, false]
    end

    def write_once(sink)
      claim_single_use!
      begin
        pump(sink)
      ensure
        @io.close if @close && @io.respond_to?(:close)
      end
    end

    # §7.1's residue, and it is this class's own rather than FileBody's (P3-28). release_replay!
    # runs in an `ensure`, and an ABANDONED enumerator never runs one: a consumer that drives
    # `stream_body.to_enum(:each)` with #next and drops it leaves @dexpace_writing set, and every
    # later write on this body raises BODY-9's "a write is already in progress" for good. Verified
    # on 3.2.11, 3.4.10 and 4.0.6, together with the two cases that are safe -- a full external
    # drive to StopIteration releases it, and #each with a break releases it. Nothing in Ruby
    # closes the abandonment case and this class does not pretend otherwise; a body that refuses
    # every later write is strictly safer than one that lets two readers share one cursor, which
    # is what BODY-9's clause exists to prevent. Design §10.10's precedent: an admitted hole beats
    # a fake proof.
    def write_replayable(sink)
      claim_replay!
      begin
        @io.seek(@origin, ::IO::SEEK_SET)
        pump(sink)
      ensure
        release_replay!
      end
    end

    # A FRESH Dexpace::IO::BufferedSource per write, for FileBody's reason: a source carried across
    # writes would replay bytes it had already buffered. It is never closed on the borrow path,
    # which is what leaves the caller's stream open -- and that is IO-6 used exactly as written
    # rather than the borrowing variant 3a declines to ship (P3-12): the wrapper's close still
    # closes the stream, this body just does not call it unless it owns the stream (plan
    # decision 7).
    def pump(sink)
      source = Dexpace::IO::BufferedSource.wrapping(@io)
      return copy_exactly(source, sink, @content_length) unless @content_length.negative?

      written = 0
      source.each { |chunk| written += emit_exactly(sink, chunk) }
      written
    end
  end
end
