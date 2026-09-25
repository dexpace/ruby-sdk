# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"

module Dexpace
  # The negotiated protocol (HTTP-33).
  #
  # The byte check runs before `downcase`, and that order is the whole reason this is code rather
  # than one line: `String#downcase` raises ArgumentError on a String carrying invalid UTF-8, and
  # an ArgumentError from inside Ruby escapes `rescue Dexpace::Error`. A validator that crashes
  # has not rejected its input. The fold itself runs on the bytes, untagged, for the same reason
  # in the other direction: a tag that cannot carry ASCII passes the byte check, and folding
  # under it raises Encoding::CompatibilityError from inside Ruby.
  class Protocol < Data.define(:wire)
    include Model

    private_class_method :new

    # The canonical lower-case wire forms a Protocol can hold. HTTP-33 names http/1.1 and http/2 as
    # EXAMPLES; http/1.0 joined in phase 10, because a real HTTP/1.0 status line is one any server
    # may send and both transports feed their native version straight to .parse -- before it, an
    # HTTP/1.0 response made both ResponseMappers raise. Additive, so NFR-4 permits it.
    WIRE_FORMS = %w[http/1.0 http/1.1 http/2].freeze
    # Every accepted spelling, folded, mapped to its canonical form; HTTP/2.0 is HTTP-33's alias.
    ALIASES = {
      "http/1.0" => "http/1.0", "http/1.1" => "http/1.1",
      "http/2" => "http/2", "http/2.0" => "http/2",
    }.freeze

    # The validating factory: accepts a canonical wire form and nothing looser, because #with
    # routes through it and a derived protocol must be exactly as canonical as a parsed one.
    def self.build(wire:)
      new(wire: wire)
    end

    # The parse-constructor: the only entry point taking raw input, case-insensitive over the
    # canonical forms and the two aliases, and idempotent on a Protocol.
    def self.parse(text)
      return text if text.is_a?(Protocol)

      identifier = Model.required!("protocol", text)
      unless identifier.is_a?(String) && printable_ascii?(identifier)
        raise InvalidArgumentError, "protocol identifier is not printable ASCII"
      end

      # `downcase` with no argument: "locale-invariant" is enforced by the repository-wide cop
      # rather than asserted here, exactly as in HTTP-13's fold. On the bytes: printable ASCII
      # hashes and compares alike under BINARY and under the table's own tag, so the lookup key
      # needs no tag at all, and a stateful one cannot reach the fold.
      canonical = ALIASES[identifier.b.downcase]
      raise InvalidArgumentError, "unrecognised protocol #{identifier.inspect}" if canonical.nil?

      build(wire: canonical)
    end

    def self.printable_ascii?(identifier)
      identifier.b.each_byte.all? { |byte| byte > 0x20 && byte < 0x7F }
    end
    private_class_method :printable_ascii?

    # Only a canonical form is a valid member; an alias or a different casing is refused, so the
    # value a Protocol holds is always the one it emits.
    def initialize(wire:)
      unless WIRE_FORMS.include?(Model.required!("wire", wire))
        raise InvalidArgumentError, "wire must be one of: #{WIRE_FORMS.join(", ")}"
      end

      super(wire: Model.frozen_string(wire))
    end

    # The canonical wire form.
    def to_s
      wire
    end

    # The HTTP/1.0 protocol, canonical instance (phase 10).
    HTTP_1_0 = build(wire: "http/1.0")
    # The HTTP/1.1 protocol, canonical instance.
    HTTP_1_1 = build(wire: "http/1.1")
    # The HTTP/2 protocol, canonical instance; `HTTP/2` and `HTTP/2.0` both parse to it.
    HTTP_2 = build(wire: "http/2")
  end
end
