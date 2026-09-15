# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Design §10.2's canonical body representation: an object responding to #each and nothing else, so
# it is exactly Dexpace::IO::_Chunked. Under this file's own frozen_string_literal pragma the
# chunks it yields from a literal array are FROZEN, which is the ordinary Rack shape and the exact
# input on which force_encoding raises (verified fact 3).
#
# `ensure_ran` records whether the #each body's ensure ran, which is §7.1's residue test, and the
# chunk list is scripted, so `FakeChunked.new("ab", "", "cd")` yields an EMPTY chunk between two
# non-empty ones -- the one input no StringIO and no IO.pipe can produce, and the one that tells
# "no bytes this time" apart from "no bytes ever".
class FakeChunked
  attr_reader :ensure_ran, :yielded

  def initialize(*chunks)
    @chunks = chunks
    @ensure_ran = false
    @yielded = 0
  end

  def each
    @chunks.each do |chunk|
      @yielded += 1
      yield chunk
    end
  ensure
    @ensure_ran = true
  end

  # The frozen non-ASCII literals every encoding test in 3a uses: an ASCII-only fixture would pass
  # under exactly the bug (verified fact 4).
  def self.frozen_utf8
    new("héllo ", "wörld")
  end
end
