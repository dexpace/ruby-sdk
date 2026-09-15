# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # A stream-contract violation: a sink asked for more bytes than the source buffer holds (IO-4),
  # a source that returned 0 for a positive requested count (IO-17), an underlying sink that
  # accepted fewer bytes than it was handed, a materialisation over Dexpace::IO's ceiling (IO-9),
  # or a reach for a TeeSink's backing buffer (IO-28).
  #
  # It subclasses ::IOError because IO-4, IO-17 and IO-42 each literally say "an I/O error" and
  # ::IOError is Ruby's root for that family. Deliberately NOT because of XCUT-4: XCUT-4 requires
  # a *transport* error to report itself as always-retryable, and a stream-contract violation must
  # not make that claim. This is a sibling of phase 8's Dexpace::TransportError inside Ruby's I/O
  # family and never a subclass of it.
  #
  # Dexpace::IOError is never defined, for the Dexpace::ArgumentError reason phase 1 recorded: it
  # would shadow ::IOError for every file inside `module Dexpace`.
  class StreamError < ::IOError
    include Dexpace::Error

    # BODY-13 requires the short-transfer message form of BODY-10/HTTP-39 to come from ONE helper
    # "so the message form cannot diverge". 3a owns the I/O half; 3b calls this. It builds and
    # returns rather than raising, so the raise site -- and its backtrace -- stays at the violation.
    def self.short_transfer(transferred:, expected:)
      new("transferred #{transferred} bytes but #{expected} were expected")
    end

    # IO-17's source-contract violation, and BODY-25's message form. One helper, same reason.
    def self.zero_read(requested:)
      new("a source returned 0 bytes for a requested count of #{requested}; " \
          "a read of 0 for a positive count is a source-contract violation (IO-17)")
    end
  end
end
