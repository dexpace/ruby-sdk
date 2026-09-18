# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A cnonce source answering SecureRandom's #hex(bytes) with one fixed value, so a Digest
# response can be asserted against a published vector (RFC 2617 §3.5's cnonce="0a4f113b",
# RFC 7616 §3.9.1's). Records the byte count it was asked for, which is AUTH-20's 16.
class FixedCnonce
  attr_reader :requests

  def initialize(value)
    @value = value
    @requests = []
  end

  def hex(bytes)
    @requests << bytes
    @value
  end
end
