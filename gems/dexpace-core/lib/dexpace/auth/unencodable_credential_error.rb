# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../error"

module Dexpace
  module Auth
    # AUTH-21's ISO-8859-1 branch is a raising path, and this is the typed failure it raises
    # (6c's R10, P6-1): a challenge that does not advertise `charset=UTF-8` fixes Latin-1 as the
    # hash-input encoding, and a username, realm or password with a character Latin-1 cannot
    # represent has no Digest response at all -- not a wrong one. `:replace` would produce a
    # well-formed header the server rejects with a 401 that cannot be told from a wrong
    # password; a bare Encoding::UndefinedConversionError gives the caller no Dexpace:: type,
    # no field and no encoding to act on. The UTF-8 branch raises the same failure, naming
    # UTF-8, for a value that is not text under its own tag -- a BINARY-tagged credential, or a
    # UTF-8-tagged one carrying an invalid sequence -- so the message says why THIS encoding
    # applied and never blames the challenge for a byte the caller supplied (6c's P6-84). The
    # message names the FIELD and the encoding, never the value (AUTH-8). #cause is the rescued
    # conversion error, or nil when the value was refused for its own invalid bytes.
    #
    # Filed under lib/dexpace/auth/ because the constant is namespaced under Auth, as phase
    # 2's Serde errors are under lib/dexpace/serde/: the file path follows the constant path.
    class UnencodableCredentialError < ::StandardError
      include Dexpace::Error

      # Why each target encoding applied, keyed by its name: the half of the message that
      # differs between the two branches.
      REASONS = {
        "UTF-8" => "the Digest challenge advertised charset=UTF-8 and the value cannot be " \
                   "transcoded to it from its own encoding",
        "ISO-8859-1" => "the Digest challenge did not advertise charset=UTF-8, so RFC 7616's " \
                        "default encoding applies",
      }.freeze
      private_constant :REASONS

      # @return [Symbol] :username, :realm or :password
      attr_reader :field
      # @return [String] the target encoding's name: "ISO-8859-1" under RFC 7616's default,
      #   "UTF-8" when the challenge advertised it and the value could not be transcoded to it
      attr_reader :encoding

      # @param field [Symbol]
      # @param encoding [String]
      def initialize(field:, encoding:)
        @field = field
        @encoding = encoding
        reason = REASONS.fetch(encoding, "no Digest hash input can be materialised under it")
        super("the #{field} cannot be encoded as #{encoding}: #{reason} (AUTH-21)")
      end
    end
  end
end
