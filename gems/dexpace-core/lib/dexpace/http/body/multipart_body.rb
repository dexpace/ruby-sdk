# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "securerandom"

require_relative "../body"
require_relative "../../model"
require_relative "../media_type"
require_relative "../header_syntax"

module Dexpace
  # HTTP-51 and BODY-2's composite body.
  #
  # ONE framing routine, #emit(sink), produces both the bytes and the declared length -- the length
  # runs it against a counting sink -- so HTTP-51's "the declared length can never drift from the
  # bytes written" is true by construction rather than by discipline. That is the highest-value
  # property test in this sub-phase.
  #
  # Not frozen, deliberately: #content_length memoises (plan decision 2). Computing it eagerly
  # would stat eight files to answer a header question that may never be asked, and a body is not
  # a Data value type (design §4's construction pattern is for the wire model, and every body
  # carries at least a media type and a length, several an open stream, and two a consume-once
  # latch).
  #
  # Part header lines are swept by phase 1's HeaderSyntax.valid_outbound_value?, the outbound
  # header grammar, which admits HTAB and printable ASCII and nothing else -- so a part name or
  # filename carrying a byte at or above 0x80 is refused, and a caller with a non-ASCII filename
  # encodes it first (RFC 7578 §4.2's percent-encoding). Stricter than a multipart part header
  # strictly needs, and the same predicate MediaType.parse applies to a part's Content-Type
  # (HTTP-26), so one grammar governs every line of the framing.
  class MultipartBody # rubocop:disable Metrics/ClassLength -- one class, its Part and HTTP-3's Builder nested; see above
    include Dexpace::Body

    # The multipart line terminator, BINARY so the framing never retags.
    CRLF = "\r\n".b.freeze
    # The boundary delimiter's prefix and the closing suffix.
    DASHES = "--".b.freeze

    # RFC 2046 bcharsnospace, which is the set a boundary may use with no trailing space. A
    # caller-supplied boundary is validated against the whole set.
    BOUNDARY_CHARS = (
      ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a + %w[' ( ) + _ , - . / : = ?]
    ).freeze
    # The length of a generated boundary: 48 of the grammar's 70, long enough that a collision
    # with a payload is not a practical concern.
    BOUNDARY_LENGTH = 48
    # A GENERATED boundary draws from the alphanumeric subset only. Every character in
    # BOUNDARY_CHARS is spec-valid, but the tspecials among them make the Content-Type parameter a
    # quoted-string, which not every peer parses; the subset is what browsers emit.
    GENERATED_BOUNDARY_CHARS = BOUNDARY_CHARS.first(62).freeze
    private_constant :GENERATED_BOUNDARY_CHARS

    # One part: a name, an optional filename, a body, and any extra part headers.
    class Part
      attr_reader :name, :filename, :body, :headers

      # Every String is copied and frozen (XCUT-15); the body is shared, because it is the thing
      # the part writes.
      def initialize(name:, body:, filename: nil, headers: {})
        @name = Dexpace::Model.required!("name", name).to_s.dup.freeze
        @body = checked_body(body)
        @filename = filename.nil? ? nil : filename.to_s.dup.freeze
        @headers = frozen_headers(headers)
        freeze
      end

      # The part's body's answer: BODY-2's conjunction is over these.
      def replayable?
        @body.replayable?
      end

      # The part's body's answer: BODY-2's collapse to -1 reads these.
      def content_length
        @body.content_length
      end

      # By value over every field, the body included -- a part over a stream body compares by
      # that body's identity, which is right.
      def ==(other)
        other.is_a?(Part) && other.name == @name && other.filename == @filename &&
          other.headers == @headers && other.body == @body
      end
      alias eql? ==

      # Agrees with #==.
      def hash
        [self.class, @name, @filename, @headers, @body].hash
      end

      private

      def checked_body(body)
        return body if Dexpace::Model.required!("body", body).is_a?(Dexpace::Body)

        raise Dexpace::InvalidArgumentError, "a part's body must be a Dexpace::Body"
      end

      def frozen_headers(headers)
        headers.to_h { |key, value| [key.to_s.dup.freeze, value.to_s.dup.freeze] }.freeze
      end
    end

    # HTTP-3's derivation target. Mutable by design and validating only in #build, so the whole of
    # #initialize's checking runs on the way out and there is no second validation site.
    class Builder
      attr_accessor :parts, :boundary, :subtype

      def initialize(parts: [], boundary: nil, subtype: "form-data")
        @parts = parts
        @boundary = boundary
        @subtype = subtype
      end

      # The body, validated on the way out exactly as a direct construction is.
      def build
        MultipartBody.new(@parts, boundary: @boundary, subtype: @subtype)
      end
    end

    attr_reader :parts, :boundary, :subtype, :media_type

    def initialize(parts, boundary: nil, subtype: "form-data")
      list = Dexpace::Model.required!("parts", parts).to_a
      unless list.all?(Part)
        raise Dexpace::InvalidArgumentError,
              "every part must be a Dexpace::MultipartBody::Part"
      end

      @parts = list.freeze
      @boundary = boundary.nil? ? self.class.generate_boundary : validate_boundary!(boundary)
      @subtype = validate_subtype!(subtype)
      @media_type = Dexpace::MediaType.parse("multipart/#{@subtype}; boundary=#{@boundary}")
      @content_length = nil
    end

    # HTTP-3, whose canonical text names "the multipart body" in the builder-based list beside
    # Request, Response, Headers, QueryParams, RequestOptions and RequestConditions. Design §4's
    # own builder list omits it, which is why phase 1 -- the ID's owner, and a phase with no
    # multipart body to build -- could not carry the clause; 3b is where the subject exists.
    #
    # The pre-filled builder MUST NOT alias this instance's internal collections, so the parts
    # list is DUPed rather than shared: later builder mutation cannot reach back into the body it
    # came from. The Part objects themselves are frozen and are shared deliberately -- HTTP-3 asks
    # that "each value list is copied", not that every value be cloned.
    def new_builder
      Builder.new(parts: @parts.dup, boundary: @boundary, subtype: @subtype)
    end

    # BODY-2: replayable if and only if EVERY constituent part is replayable.
    def replayable?
      @parts.all?(&:replayable?)
    end

    # BODY-2: the declared length collapses to the -1 sentinel if any part's length is unknown.
    # Otherwise it is the byte count the framing routine actually produces, computed lazily and
    # memoised. -1 is truthy in Ruby, so ||= memoises the sentinel correctly too.
    def content_length
      @content_length ||= compute_content_length
    end

    # The framing routine, writing for real.
    def write_to(sink)
      emit(sink)
    end

    # HTTP-51: 1..70 characters from bcharsnospace, generated with SecureRandom (already on phase
    # 0's require allowlist).
    def self.generate_boundary
      bytes = ::SecureRandom.bytes(BOUNDARY_LENGTH)
      alphabet = GENERATED_BOUNDARY_CHARS
      bytes.each_byte.map { |byte| alphabet.fetch(byte % alphabet.length) }.join.freeze
    end

    # HTTP-46: by value, over the boundary and the parts that determine the bytes.
    def ==(other)
      other.is_a?(MultipartBody) && other.boundary == @boundary && other.parts == @parts
    end
    alias eql? ==

    # Agrees with #==.
    def hash
      [self.class, @boundary, @parts].hash
    end

    private

    def compute_content_length
      return -1 if @parts.any? { |part| part.content_length.negative? }

      emit(counting_sink, count_only: true)
    end

    # THE one framing routine. #write_to and #content_length both run it; nothing else writes a
    # boundary or a part header, which is what HTTP-51's SHOULD is for.
    #
    # `count_only:` changes exactly one line, and it has to (P3-29). Writing the part bodies to
    # the counting sink would mean a HEADER QUESTION consumes them: a part that is single-use but
    # length-known -- Body.stream(io, content_length: 6, close: true), Body.chunked(chunks,
    # content_length: 4), a pipe-backed stream with a declared length -- is drained (and, with
    # close: true, closed) by #content_length, and the write that follows raises BODY-6. Every
    # FileBody part would also be read off disk in full to answer it. The FRAMING bytes still
    # come from this one routine, which is the drift HTTP-51 exists to prevent; the payload count
    # is the part's own HTTP-36 declared length, and BODY-2's sentinel above is what covers the
    # case where it is not known.
    def emit(sink, count_only: false)
      delimiter = DASHES + @boundary.b + CRLF
      written = @parts.sum { |part| emit_part(sink, part, delimiter, count_only) }
      written + emit_exactly(sink, DASHES + @boundary.b + DASHES + CRLF)
    end

    def emit_part(sink, part, delimiter, count_only)
      emit_exactly(sink, delimiter) + emit_exactly(sink, part_headers(part)) +
        payload(sink, part, count_only) + emit_exactly(sink, CRLF)
    end

    # The one line #emit's counting run changes (P3-29).
    def payload(sink, part, count_only)
      count_only ? part.content_length : part.body.write_to(sink)
    end

    # The part's header block, one assembled line at a time, each swept by phase 1's outbound
    # header grammar so a caller-supplied part header is caught by the same predicate as a
    # parameter value and not by a second copy of it.
    def part_headers(part)
      lines = [disposition(part)]
      media = part.body.media_type
      lines << "Content-Type: #{media.render}" unless media.nil?
      part.headers.each { |key, value| lines << "#{key}: #{value}" }
      lines.each { |line| sweep!(line) }
      "#{lines.join(CRLF)}\r\n\r\n".b
    end

    def disposition(part)
      line = "Content-Disposition: form-data; name=#{quote(part.name)}"
      return line if part.filename.nil?

      "#{line}; filename=#{quote(part.filename)}"
    end

    def sweep!(line)
      return nil if Dexpace::HeaderSyntax.valid_outbound_value?(line)

      raise Dexpace::InvalidArgumentError,
            "part header #{line.inspect} carries a byte no header value may carry (HTTP-51)"
    end

    # HTTP-51's one MUST inside a SHOULD: a CR, an LF or a quote in a parameter value must not be
    # able to break the framing. A backslash and a quote are escaped; a CR or an LF is REJECTED
    # rather than escaped, because RFC 7578's quoted-string has no representation for them and an
    # escaped CRLF would still be a CRLF on the wire.
    def quote(value)
      if value.include?("\r") || value.include?("\n")
        raise Dexpace::InvalidArgumentError,
              "a multipart parameter value must not contain CR or LF, got #{value.inspect}"
      end

      %("#{value.gsub(/[\\"]/) { |match| "\\#{match}" }}")
    end

    # The subtype is one bare token and nothing more: a caller's "form-data;x=1" would otherwise
    # parse as a subtype plus a smuggled parameter, and the media type would say one thing while
    # #subtype said another. MediaType.parse is the token grammar, so it is not written twice.
    def validate_subtype!(subtype)
      text = subtype.to_s
      parsed = Dexpace::MediaType.parse("multipart/#{text}")
      return text.dup.freeze if parsed.parameters.empty? && parsed.subtype == text

      raise Dexpace::InvalidArgumentError,
            "subtype #{text.inspect} must be a bare lower-case multipart subtype token"
    end

    def validate_boundary!(boundary)
      text = boundary.to_s
      unless (1..70).cover?(text.length) && text.each_char.all? { |c| BOUNDARY_CHARS.include?(c) }
        raise Dexpace::InvalidArgumentError,
              "boundary #{text.inspect} violates RFC 2046's 1-70 bcharsnospace grammar (HTTP-51)"
      end

      text.dup.freeze
    end
  end
end
