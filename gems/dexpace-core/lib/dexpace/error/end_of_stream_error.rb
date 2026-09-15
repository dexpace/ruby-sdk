# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # End of stream reached by a read form that cannot report it any other way: #read_exactly,
  # #readbyte, #readpartial, #skip (IO-11, IO-12, IO-15, IO-16).
  #
  # The superclass is load-bearing, not tidy. Verified on 3.2.11, 3.4.10 and 4.0.6 that
  # IO.copy_stream -- which is literally what Net::HTTP#send_request_with_body_stream calls, so it
  # is the code path every streamed upload takes -- terminates cleanly on an ::EOFError SUBCLASS
  # raised by a duck-typed #readpartial. Outside that family copy_stream propagates and every
  # upload phase 8 performs fails. Ruby's own readers raise ::EOFError for exactly this condition.
  #
  # Dexpace::EOFError is never defined, for the Dexpace::ArgumentError reason phase 1 recorded.
  class EndOfStreamError < ::EOFError
    include Dexpace::Error
  end
end
