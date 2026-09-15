# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require "stringio"

# IO-11, IO-12, IO-15, IO-16.
class DexpaceEndOfStreamErrorTest < DexpaceTestCase
  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise Dexpace::EndOfStreamError, "eof"
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::EndOfStreamError, caught)
  end

  # THE ancestry assertion, and it is load-bearing rather than tidy. Verified on 3.2.11, 3.4.10 and
  # 4.0.6 that IO.copy_stream -- which is literally what Net::HTTP#send_request_with_body_stream
  # calls -- terminates CLEANLY on an ::EOFError SUBCLASS raised by a duck-typed #readpartial.
  # Outside that family copy_stream propagates and every streaming upload phase 8 performs fails,
  # and nothing else in 3a would catch it.
  test "inherits ::EOFError, which is what makes IO.copy_stream terminate rather than propagate" do
    assert_operator(Dexpace::EndOfStreamError, :<, ::EOFError)
  end

  # The proof, not the restatement: a duck-typed source that raises this class drives
  # IO.copy_stream to a clean finish with the payload intact.
  test "IO.copy_stream terminates on it and keeps the payload" do
    source = Class.new do
      def initialize = @remaining = 3

      def readpartial(_maxlen, outbuf = nil)
        raise Dexpace::EndOfStreamError, "done" if @remaining.zero?

        @remaining -= 1
        outbuf.nil? ? +"xy" : outbuf.replace(+"xy")
      end
    end.new
    destination = StringIO.new(+"".b)

    ::IO.copy_stream(source, destination)

    assert_equal("xyxyxy", destination.string)
  end

  # A ::StandardError, so `rescue => e` catches it; it is deliberately NOT in the IOError family,
  # because IO-24 requires end of stream to stay distinct from a state/contract failure.
  test "is not a Dexpace::StreamError, so EOF and a contract violation stay distinct" do
    refute_operator(Dexpace::EndOfStreamError, :<, Dexpace::StreamError)
    assert_operator(Dexpace::EndOfStreamError, :<, ::StandardError)
  end
end
