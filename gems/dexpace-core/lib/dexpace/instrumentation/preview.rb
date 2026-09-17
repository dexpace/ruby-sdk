# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-38: the body-preview renderer -- charset-aware for text, size-only for anything else,
    # and total. A module with no instance side: it takes the captured bytes a logging wrapper
    # mirrored and a media type, and it neither acquires nor closes a body.
    #
    # Text or binary is decided by the media type and the decision is chosen (P5-31): a payload
    # is text when its type is `text`, or its subtype is one of TEXT_SUBTYPES, or its subtype
    # carries an RFC 6839 `+json` / `+xml` structured-syntax suffix; everything else, an ABSENT
    # media type included, is binary and gets the `[binary N bytes captured]` marker. Defaulting
    # an unknown type to binary is the safe direction, because rendering unknown bytes as text
    # is how a log line acquires a control character or a partial credential.
    #
    # The text path is phase 3b's corrected decode recipe and not design §3.1's sentence, which
    # is on phase 10's inbound list: RETAG the BINARY bytes with the declared charset, then
    # transcode with both encodings named and replacement for anything invalid or undefined.
    # Transcoding straight from BINARY -- §3.1's one step -- replaces every non-ASCII byte
    # (verified fact 11). "Decoding MUST NOT throw" is met by the replacement options for every
    # byte sequence, and by a fallback for the one thing the options do not cover: a charset the
    # interpreter KNOWS but cannot convert. `Encoding.find("utf-7")` and `("iso-2022-jp-2")`
    # answer a dummy encoding with no converter, MediaType#charset therefore answers the name
    # rather than nil, and `#encode` raises Encoding::ConverterNotFoundError with the replacement
    # options set (review round 1's R1-4, P5-106); such a charset is decoded as UTF-8, the same
    # fallback an unrecognised charset takes, so the two "cannot decode as declared" cases have
    # one answer. The charset arrives already folded and already `nil` for absent or
    # unrecognised through MediaType#charset (HTTP-24), so `Encoding.find` cannot raise for a
    # Dexpace::MediaType and is guarded anyway for a duck-typed one.
    module Preview
      # OBS-38's size-only marker, a format taking the byte count.
      BINARY_MARKER_FORMAT = "[binary %d bytes captured]"

      # The non-`text/*` subtypes rendered as text, in addition to any `+json` / `+xml` suffix.
      TEXT_SUBTYPES = ::Set[
        "json", "xml", "yaml", "csv", "javascript", "graphql", "x-www-form-urlencoded", "x-ndjson",
      ].freeze

      # RFC 6839's two structured-syntax suffixes. Per-pattern timeout, never Regexp.timeout,
      # which would impose a process-wide budget on the host. Private: P5-16 names this module's
      # two public constants and no third.
      SUFFIX_PATTERN = ::Regexp.new('\+(?:json|xml)\z', timeout: 1.0)
      private_constant :SUFFIX_PATTERN

      # Renders a captured preview.
      #
      # @param bytes [String, nil] the captured bytes, normally BINARY; read by their bytes
      #   whatever their tag, and never mutated
      # @param media_type [Dexpace::MediaType, #type, #subtype, #charset, nil] the body's media
      #   type; nil is binary
      # @return [String] a UTF-8 text preview, the binary marker, or "" for empty input
      def self.render(bytes, media_type:)
        return "" if bytes.nil? || bytes.empty?
        return binary_marker(bytes) if media_type.nil? || !text?(media_type)

        decode(bytes, media_type.charset)
      end

      # P5-31's discriminator over an already-folded type and subtype (HTTP-23 folds both at
      # construction, so this writes no fold of its own).
      def self.text?(media_type)
        return true if media_type.type == "text"

        subtype = media_type.subtype
        TEXT_SUBTYPES.include?(subtype) || SUFFIX_PATTERN.match?(subtype)
      end
      private_class_method :text?

      # Phase 3b's recipe through the declared charset, falling back to UTF-8 for a charset with
      # no converter. `EncodingError` and not `ConverterNotFoundError` alone: that is the one
      # member of the family the replacement options leave reachable, and the fallback is total
      # for the family rather than for one name in it (XCUT-20). The fallback cannot itself
      # raise -- UTF-8 to UTF-8 with both replacements is a scrub.
      def self.decode(bytes, charset)
        transcode(bytes, encoding_for(charset))
      rescue ::EncodingError
        transcode(bytes, ::Encoding::UTF_8)
      end
      private_class_method :decode

      # Retag, then transcode with both encodings named.
      def self.transcode(bytes, encoding)
        retagged = bytes.b.force_encoding(encoding)
        retagged.encode(::Encoding::UTF_8, encoding, invalid: :replace, undef: :replace)
      end
      private_class_method :transcode

      # The declared charset as an Encoding, UTF-8 when absent or unknown. MediaType#charset is
      # already nil for the unknown case; the rescue is for a duck-typed media type.
      def self.encoding_for(charset)
        return ::Encoding::UTF_8 if charset.nil?

        ::Encoding.find(charset) || ::Encoding::UTF_8
      rescue ::ArgumentError
        ::Encoding::UTF_8
      end
      private_class_method :encoding_for

      def self.binary_marker(bytes)
        ::Kernel.format(BINARY_MARKER_FORMAT, bytes.bytesize)
      end
      private_class_method :binary_marker
    end
  end
end
