# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "scripted_transport"

# The async twin of ScriptedTransport (SEAM-16): the same script -- a callable, an Exception or a
# response per call, in order -- delivered through a fresh Completer per call. By default each
# future settles INLINE, inside #call, which is the shape a scripted downstream has and the shape
# that made the plan's recursive pump overflow (RETRY-30); with `settle_later: true` every future
# is left pending and #settle_next! settles the oldest unsettled one, so a test can hold an
# attempt in flight, cancel the returned future, and then let the attempt land (RETRY-32).
#
# A Proc entry is invoked with (request, options, cancellation) and its answer -- a Response or an
# Exception -- is what the future settles with, so a script can cancel a token from inside the
# attempt it is serving. #calls and the three-positional #call are ScriptedTransport's.
class ScriptedAsyncTransport
  attr_reader :pending

  def initialize(script, settle_later: false)
    @inner = ScriptedTransport.new(script)
    @settle_later = settle_later
    @pending = []
    @mutex = ::Thread::Mutex.new
  end

  def calls = @inner.calls

  def call(request, options, cancellation)
    completer = Dexpace::Async::Completer.new
    outcome = begin
      [@inner.call(request, options, cancellation), nil]
    rescue ::StandardError => error
      [nil, error]
    end
    if @settle_later
      @mutex.synchronize { @pending << [completer, outcome] }
    else
      deliver(completer, outcome)
    end
    completer.future
  end

  # Settles the oldest pending future; nil when none is pending.
  def settle_next!
    entry = @mutex.synchronize { @pending.shift }
    return nil if entry.nil?

    deliver(*entry)
    true
  end

  private

  def deliver(completer, outcome)
    response, error = outcome
    error.nil? ? completer.fulfil(response) : completer.fail(error)
  end
end
