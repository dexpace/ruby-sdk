# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# A bearer provider with a genuine #fetch_async: each call pops one script item -- a
# Dexpace::Async::Future is returned as it is (an unsettled one is how a test holds the fetch
# open and settles it deliberately), an Exception is RAISED synchronously (AUTH-11's
# "misbehaving async override"), a callable is called and its result returned, and anything
# else is returned as the fetch_async result (a non-Future, for the normalisation case). The
# last item repeats. #fetch exists because the provider duck type requires it, and raises: a
# test that lands on it has driven the wrong path.
class ScriptedAsyncBearerProvider
  attr_reader :fetches

  def initialize(*script)
    raise ArgumentError, "a script needs at least one item" if script.empty?

    @script = script
    @fetches = 0
    @mutex = ::Thread::Mutex.new
  end

  def fetch
    raise "ScriptedAsyncBearerProvider#fetch: the async path was expected"
  end

  def fetch_async
    item = @mutex.synchronize do
      @fetches += 1
      @script.size > 1 ? @script.shift : @script.first
    end
    raise item if item.is_a?(Exception)

    item.respond_to?(:call) && !item.is_a?(Dexpace::Async::Future) ? item.call : item
  end
end
