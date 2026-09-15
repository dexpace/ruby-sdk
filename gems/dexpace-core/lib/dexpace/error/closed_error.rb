# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised by a seam implementation when it is used after #close.
  #
  # SEAM-15 is a MAY -- "further send calls MAY have undefined behavior ... A port MAY choose a
  # mode but SHOULD document it" -- and this port chooses and documents one, because "undefined"
  # in Ruby means whatever NoMethodError the internals happen to produce. The documented mode is
  # narrower than "a send after close raises": a transport that OWNS the resource it closed
  # raises this from a later send, while a wrapper that only borrows (both SEAM-18 bridges)
  # closes nothing and stays usable, which is what XCUT-22's "the caller owns its lifecycle"
  # requires. Phase 2 ships the class and the rule and no raise site; phase 8's adapters are the
  # first owners and dexpace-conformance asserts the raise per adapter.
  class ClosedError < ::StandardError
    include Dexpace::Error
  end
end
