# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A response-body delegate whose #close RAISES, which BODY-27 ("if the delegate's close throws it
# MUST still be marked closed") and BODY-28 ("a close failure after a successful full capture MUST
# NOT be reported as a drain error") both require and which no StringIO will do.
#
# It is deliberately NOT a Dexpace::ResponseBody: the wrapper's contract on its delegate is #source,
# #content_length, #media_type and #close, and this is exactly that and nothing more.
class FakeResponseBody
  attr_reader :source, :media_type, :content_length, :closes

  def initialize(source, media_type: nil, content_length: -1, close_error: nil)
    @source = source
    @media_type = media_type
    @content_length = content_length
    @close_error = close_error
    @closes = 0
  end

  def close
    @closes += 1
    raise @close_error unless @close_error.nil?

    nil
  end
end
