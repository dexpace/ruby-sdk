# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# SequencedTransport's SEAM-16 twin: one script item per call, returned as a future -- a
# Dexpace::Response becomes a settled future, an Exception a failed one, a Dexpace::Async::Future
# is returned as it is (an unsettled one is how a test holds a drive open), and a callable is
# called with the request and its result treated the same way. Records the same triples.
class SequencedAsyncTransport
  attr_reader :calls

  def initialize(*script)
    @script = script
    @calls = []
    @mutex = ::Thread::Mutex.new
  end

  def call(request, options, cancellation)
    item = @mutex.synchronize do
      @calls << [request, options, cancellation]
      raise "SequencedAsyncTransport: no scripted reply for drive #{@calls.size}" if @script.empty?

      @script.shift
    end
    item = item.call(request) if item.respond_to?(:call) && !item.is_a?(Dexpace::Async::Future)
    as_future(item)
  end

  def as_future(item)
    return item if item.is_a?(Dexpace::Async::Future)

    completer = Dexpace::Async::Completer.new
    item.is_a?(Exception) ? completer.fail(item) : completer.fulfil(item)
    completer.future
  end

  def requests = @calls.map(&:first)

  def authorization_headers
    requests.map { |request| request.headers["Authorization"]&.first }
  end
end
