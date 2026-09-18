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
    # no field and no encoding to act on. The message names the FIELD and the encoding, never
    # the value (AUTH-8). #cause is the rescued conversion error.
    #
    # Filed under lib/dexpace/auth/ because the constant is namespaced under Auth, as phase
    # 2's Serde errors are under lib/dexpace/serde/: the file path follows the constant path.
    class UnencodableCredentialError < ::StandardError
      include Dexpace::Error

      # @return [Symbol] :username, :realm or :password
      attr_reader :field
      # @return [String] the target encoding's name, "ISO-8859-1"
      attr_reader :encoding

      # @param field [Symbol]
      # @param encoding [String]
      def initialize(field:, encoding:)
        @field = field
        @encoding = encoding
        super("the #{field} cannot be encoded as #{encoding}: the Digest challenge did not " \
              "advertise charset=UTF-8, so RFC 7616's default encoding applies (AUTH-21)")
      end
    end
  end
end
