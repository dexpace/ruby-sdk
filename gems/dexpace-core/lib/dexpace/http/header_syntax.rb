# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/invalid_argument_error"

module Dexpace
  # The header grammar, as bytes.
  #
  # Public API on purpose: HTTP-17/HTTP-18/XCUT-18 are re-checked at the model-to-wire boundary
  # inside every transport adapter (phase 8a Task 16, phase 8c Task 9), and an adapter lives in a
  # different gem, so it must be able to reach the predicate without building a model. That
  # re-check is what makes the encapsulation gap of design §10.10 a correctness-of-shape gap
  # rather than a request-splitting one.
  #
  # Every predicate reads `value.b.each_byte`, never a character regexp: a String carrying
  # invalid UTF-8 is exactly the input this module exists to reject, and a character operation
  # on one raises ArgumentError or Encoding::CompatibilityError from inside Ruby instead of
  # returning false. A validator that crashes has not rejected its input.
  module HeaderSyntax
    extend self

    # Horizontal tab: the one control byte a field value may carry (HTTP-18, HTTP-19).
    HTAB = 0x09
    # The space byte: trimmed from around a name (HTTP-17), never permitted inside one.
    SPACE = 0x20
    # DEL: rejected in every position by both grammars.
    DEL = 0x7F
    # The two bytes #trim removes from around a name, and the only two. An implementation detail
    # of #trim rather than part of the grammar a transport re-checks, so it is kept out of the
    # public surface NFR-4 locks at the first release tag.
    TRIMMABLE = [SPACE, HTAB].freeze
    private_constant :TRIMMABLE
    # RFC 7230 tchar, as BYTES: the grammar of a method token, a media-type component and a
    # bare parameter value. tchar is ASCII-only, so a byte test is exact as well as total.
    TCHAR = [
      *"0".."9", *"A".."Z", *"a".."z",
      "!", "#", "$", "%", "&", "'", "*", "+", "-", ".", "^", "_", "`", "|", "~",
    ].map(&:ord).freeze

    # HTTP-17's "surrounding whitespace is trimmed before validation" -- SP and HTAB only.
    #
    # Not String#strip, twice over. It also strips NUL, so "a\0" would trim to "a" and pass the
    # check that exists to reject NUL; and it raises Encoding::CompatibilityError on a name
    # carrying invalid UTF-8, which is an input this function must REJECT rather than crash on.
    # Trimming CR or LF would be worse still: "a\r\n" would become a valid name.
    #
    # The result is the surviving BYTES, tagged BINARY: this function is total over any String,
    # including one whose bytes are invalid in its own encoding, so it cannot promise a tag.
    def trim(name)
      bytes = name.b
      start = 0
      finish = bytes.bytesize
      start += 1 while start < finish && trimmable?(bytes.getbyte(start))
      finish -= 1 while finish > start && trimmable?(bytes.getbyte(finish - 1))
      # byteslice is typed String? for a start past the end; start never is, so the alternative
      # is unreachable and only keeps the declared return type honest.
      bytes.byteslice(start, finish - start) || ""
    end

    # HTTP-17: no C0 control, no DEL, no byte >= 0x80, not blank. Every byte below 0x21 is
    # rejected, which covers the controls, SP and HTAB -- a header name has no interior space.
    def valid_name?(name)
      trimmed = trim(name)
      return false if trimmed.empty?

      trimmed.each_byte.none? { |byte| byte < 0x21 || byte == DEL || byte >= 0x80 }
    end

    # HTTP-18: HTAB plus printable ASCII 0x20-0x7E, and nothing else.
    def valid_outbound_value?(value)
      value.b.each_byte.all? { |byte| byte == HTAB || (byte >= SPACE && byte < DEL) }
    end

    # HTTP-19: the same rule with the non-ASCII clause relaxed, because RFC 7230 permits obs-text
    # in a field value and applying the outbound grammar to a response would silently drop a
    # legitimate Latin-1 Content-Disposition.
    def valid_inbound_value?(value)
      value.b.each_byte.all? { |byte| byte == HTAB || (byte >= SPACE && byte != DEL) }
    end

    # The trimmed name when it is valid; otherwise HTTP-20's escaped echo of it in the message.
    #
    # A valid name is printable ASCII, which every ASCII-compatible encoding spells identically,
    # so the trimmed bytes are retagged with the caller's own encoding: `force_encoding` is a
    # retag used only where the bytes are known to conform, and here they are proven to.
    def validate_name!(name)
      return trim(name).force_encoding(name.encoding) if valid_name?(name)

      raise InvalidArgumentError,
            "header name #{escape(name)} is not a valid field name (HTTP-17)"
    end

    # The value unchanged when the outbound grammar accepts it. The message names the header and
    # never the value (HTTP-20).
    def validate_outbound_value!(value, name:)
      return value if valid_outbound_value?(value)

      raise InvalidArgumentError,
            "value for header #{escape(name)} contains a byte no outbound header value may " \
            "carry (HTTP-18)"
    end

    # The value unchanged when the inbound grammar accepts it; the same no-echo rule applies.
    def validate_inbound_value!(value, name:)
      return value if valid_inbound_value?(value)

      raise InvalidArgumentError,
            "value for header #{escape(name)} contains a control byte (HTTP-19)"
    end

    # RFC 7230 token: one or more tchar. Not a regexp: `Regexp#match?` raises ArgumentError on a
    # String carrying invalid UTF-8, and an ArgumentError raised from inside Ruby escapes
    # `rescue Dexpace::Error` -- a validator that crashes has not rejected its input.
    def token?(text)
      bytes = text.b
      !bytes.empty? && bytes.each_byte.all? { |byte| TCHAR.include?(byte) }
    end

    # HTTP-20: a rejected VALUE never appears in a message in any form, and a name is echoed with
    # its control bytes escaped, so a rejected header cannot inject a line into a log.
    def escape(name)
      escaped = name.to_s.b.each_byte.map do |byte|
        byte < SPACE || byte == DEL || byte >= 0x80 ? format("\\x%02X", byte) : byte.chr
      end
      escaped.join
    end

    private

    def trimmable?(byte)
      TRIMMABLE.include?(byte)
    end
  end
end
