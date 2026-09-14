# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # RFC 3986 percent-encoding for a single component (HTTP-29, HTTP-32; design §3.5).
  #
  # This is NOT application/x-www-form-urlencoded, and the form encoder BODY-35 needs is a
  # different function with a different name in a later phase. They are never interchanged: the
  # difference is a space, which is %20 here and "+" there, and a URL that mixes them is wrong in
  # a way no test of either function alone would catch.
  #
  # Both directions read bytes and neither uses a regexp: a value carrying invalid UTF-8 encodes
  # byte-exactly instead of raising, and a percent-escape is two hex bytes whatever the string's
  # tag says.
  module PercentEncoding
    extend self

    # RFC 3986's unreserved set, as bytes: A-Z a-z 0-9 - . _ ~ and nothing else.
    UNRESERVED = [*"A".."Z", *"a".."z", *"0".."9", "-", ".", "_", "~"].map(&:ord).freeze
    # Every byte's escape, precomputed and uppercase.
    ENCODED = (0..255).to_h { |byte| [byte, format("%%%02X", byte)] }.freeze
    # The byte value of each hex digit, both cases.
    HEX_VALUES = [*"0".."9", *"A".."F", *"a".."f"]
      .to_h { |digit| [digit.ord, digit.to_i(16)] }.freeze
    # The "%" byte that opens an escape.
    PERCENT = 0x25

    # HTTP-29 / HTTP-32: every byte outside the unreserved set is percent-encoded, uppercase --
    # space to %20, "+" to %2B, "/" to %2F, "*" to %2A -- and "~" is left bare.
    def encode_component(text)
      text.b.each_byte.map { |byte| passthrough(byte) || ENCODED.fetch(byte) }.join
    end

    # HTTP-31: lenient and total. A malformed escape is left exactly as it was found rather than
    # raising, which is the opposite of URI.decode_www_form_component's behaviour and the reason
    # this is hand-rolled. HTTP-32: "+" decodes to "+", never to a space.
    #
    # The accumulator is BINARY because appending a high byte to a UTF-8 buffer raises
    # Encoding::CompatibilityError. The closing `force_encoding` is a retag, not a conversion:
    # the bytes are whatever the sender sent, every comparison downstream is byte-wise, and the
    # label says only which encoding a caller should read them as.
    def decode_component(text)
      bytes = text.b
      out = String.new(encoding: Encoding::BINARY)
      index = 0
      bytes.each_byte.with_index do |byte, position|
        next if position < index

        decoded = escape_at(bytes, position)
        out << (decoded || byte).chr
        index = position + (decoded ? 3 : 1)
      end
      out.force_encoding(Encoding::UTF_8)
    end

    private

    # The byte itself as a character when it is unreserved, else nil.
    def passthrough(byte)
      UNRESERVED.include?(byte) ? byte.chr : nil
    end

    # The byte a well-formed "%XX" at `index` denotes, or nil when there is no such escape there.
    def escape_at(bytes, index)
      return nil unless bytes.getbyte(index) == PERCENT

      high = HEX_VALUES[bytes.getbyte(index + 1)]
      low = HEX_VALUES[bytes.getbyte(index + 2)]
      return nil if high.nil? || low.nil?

      (high << 4) | low
    end
  end
end
