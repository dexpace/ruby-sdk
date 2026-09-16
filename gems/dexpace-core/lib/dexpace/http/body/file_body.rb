# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../../model"

module Dexpace
  # HTTP-40/BODY-11's file body: replayable, a FRESH ::File handle per write, and fail-fast
  # construction validating six clauses before any write is attempted.
  #
  # BODY-12's first clause is implemented here through ::IO.copy_stream(handle, sink, count,
  # offset), which is core Ruby (no require), accepts a duck-typed #write destination, honours the
  # (length, offset) window, leaves the handle's own cursor untouched when an offset is given, and
  # returns the byte count -- which is BODY-13's short-write detection for free. It is also the call
  # that becomes a real kernel sendfile/copy_file_range the moment both ends are real ::IOs, which
  # is what clause 2 is waiting for (a transport obligation, TRANSPORT-28's, phase 8; declined there
  # by 8a's R5 and stated in docs/first-release.md under "What v1 ships without"). P3-17.
  #
  # #to_path IS DELIBERATELY NOT DEFINED, and that is the whole of BODY-12's clause-2 answer from
  # this side. Verified on 3.2.11, 3.4.10 and 4.0.6: ::IO.copy_stream checks respond_to?(:to_path)
  # first, and copy_stream(body, sink) with NO length then copies the WHOLE FILE -- so a transport
  # doing the obvious thing would silently upload every byte of the file and ignore this body's
  # offset+count window. #path, #offset and #count are public instead, which is what "recognizable
  # by type so transports can dispatch a true zero-copy kernel path" actually needs.
  #
  # §7.1's residue, stated rather than closed (P3-21). BODY-11 requires a fresh handle per write,
  # so the handle cannot live on the object and #close cannot release it. A consumer that drives
  # `file_body.to_enum(:each)` with #next and abandons it before exhaustion LEAKS that handle: the
  # ensure below does not run, #rewind does not run it, and GC.start is not a cleanup hook -- all
  # verified on 3.2.11, 3.4.10 and 4.0.6, and `docs/knowledge/notes/pagination.md` records that an
  # ordinary #each method leaks exactly like an Enumerator.new block. A FULL external drive to
  # StopIteration does run it, so BufferedSource.over(file_body) driven to exhaustion is safe, and
  # internal iteration with a break runs it too. Nothing in Ruby closes the abandonment case and
  # this class does not pretend otherwise; design §10.10's precedent is that an admitted hole beats
  # a fake proof, and `resource-management/1676974d` is why a finalizer is not the answer. The
  # residue travels: a MultipartBody with a file part or a RequestLoggingBody over one inherits it,
  # because #each is derived from #write_to and the abandonment suspends inside the enclosing
  # body's write just as it does inside this one.
  class FileBody
    include Dexpace::Body

    attr_reader :path, :offset, :count, :media_type

    # BODY-11's six clauses, in this order, each raising Dexpace::InvalidArgumentError naming the
    # argument, and all of them before any I/O beyond one ::File.stat. `count: nil` is the
    # rest-of-file sentinel and resolves to size - offset at construction, so #count is always an
    # exact Integer -- HTTP-40's "MUST expose the exact byte count it will upload".
    def initialize(path, media_type: nil, offset: 0, count: nil)
      target = Dexpace::Model.required!("path", path).to_s
      validate_target!(target)
      validate_window!(offset, count)

      @path = target.dup.freeze
      @offset = offset
      @count = resolve_count(target, offset, count)
      @media_type = media_type
      freeze
    end

    # HTTP-40's exact byte count: the window resolved at construction.
    def content_length
      @count
    end

    # BODY-11: replayable, because every write opens its own handle and reads its own window, so
    # concurrent and repeated sends are safe at the body level with no shared cursor to race on.
    def replayable?
      true
    end

    # A fresh handle per write, closed on every exit by ::File.open's block form; the transfer is
    # ::IO.copy_stream's, with the window given explicitly so the handle's own cursor is never
    # consulted.
    def write_to(sink)
      return 0 if @count.zero?

      ::File.open(@path, "rb") do |handle|
        # rbs's ::IO.copy_stream wants a `_Writer` -- `write: (*untyped)` -- and a _Sink's
        # `write: (*String)` is narrower on its parameter, so the structural check fails on
        # variance alone; at runtime copy_stream calls #write with one String.
        destination = sink #: untyped
        transferred = ::IO.copy_stream(handle, destination, @count, @offset)
        if transferred < @count
          raise Dexpace::StreamError.short_transfer(transferred: transferred, expected: @count)
        end

        transferred
      end
    end

    # HTTP-46: by value, over path, offset, count and media type -- the four facts that determine
    # the bytes.
    def ==(other)
      other.is_a?(FileBody) && other.path == @path && other.offset == @offset &&
        other.count == @count && other.media_type == @media_type
    end
    alias eql? ==

    # Agrees with #==.
    def hash
      [self.class, @path, @offset, @count, @media_type].hash
    end

    private

    # BODY-11's first two clauses. Split out of #initialize for Metrics/MethodLength's 25, and
    # the split is by clause group rather than by line count.
    def validate_target!(target)
      unless ::File.exist?(target)
        raise Dexpace::InvalidArgumentError, "path #{target.inspect} does not exist"
      end
      return if ::File.file?(target)

      raise Dexpace::InvalidArgumentError, "path #{target.inspect} is not a regular file"
    end

    # BODY-11's offset and count shape clauses, before any I/O beyond the one ::File.stat below.
    def validate_window!(offset, count)
      unless offset.is_a?(::Integer) && !offset.negative?
        raise Dexpace::InvalidArgumentError,
              "offset must be a non-negative Integer, got #{offset.inspect}"
      end
      return if count.nil? || (count.is_a?(::Integer) && !count.negative?)

      raise Dexpace::InvalidArgumentError,
            "count must be a non-negative Integer or nil for the rest of the file, " \
            "got #{count.inspect}"
    end

    # BODY-11's last two clauses, and HTTP-40's "MUST expose the exact byte count it will upload":
    # `count: nil` is the rest-of-file sentinel and resolves against the size captured HERE, so
    # #count is always an exact Integer.
    def resolve_count(target, offset, count)
      size = ::File.stat(target).size
      if offset > size
        raise Dexpace::InvalidArgumentError,
              "offset #{offset} is past the end of a #{size}-byte file"
      end
      span = count.nil? ? size - offset : count
      return span if offset + span <= size

      raise Dexpace::InvalidArgumentError,
            "offset #{offset} plus count #{span} exceeds the #{size}-byte size captured at " \
            "construction"
    end
  end
end
