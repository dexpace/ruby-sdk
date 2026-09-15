# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The in-memory async fake: implements only SEAM-16, and settles its future synchronously unless a
# `settle_later` block is supplied, so a test can drive the completion race deliberately.
class FakeAsyncTransport
  attr_reader :calls, :completer

  def initialize(response: nil, raises: nil, settle_later: false)
    @response = response
    @raises = raises
    @settle_later = settle_later
    @calls = []
  end

  def call(request, options, cancellation)
    @calls << [request, options, cancellation]
    @completer = Dexpace::Async::Completer.new
    settle unless @settle_later
    @completer.future
  end

  def settle
    return @completer.fail(@raises) if @raises

    @completer.fulfil(@response)
  end
end
