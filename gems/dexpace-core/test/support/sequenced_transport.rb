# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A transport that answers a SCRIPT, one item per call, in order: a Dexpace::Response is
# returned, an Exception is raised, a callable is called with the request and its result
# returned. Every 401-then-200 test of the AUTH step needs one, and FakeTransport answers one
# fixed response. Records every [request, options, cancellation] triple, like FakeTransport,
# and raises loudly when the script runs out, so an unexpected extra drive fails the test
# instead of returning nil into a step.
#
# Named SequencedTransport and not ScriptedTransport: phase 6a is building a double of the
# latter name in the same file position at the same time, and the two lanes merge without a
# collision this way; the duplication is the manager's to reconcile after both land.
class SequencedTransport
  # @return [Array<Array>] one [request, options, cancellation] triple per call
  attr_reader :calls

  def initialize(*script)
    @script = script
    @calls = []
    @mutex = ::Thread::Mutex.new
  end

  def call(request, options, cancellation)
    item = @mutex.synchronize do
      @calls << [request, options, cancellation]
      raise "SequencedTransport: no scripted reply for drive #{@calls.size}" if @script.empty?

      @script.shift
    end
    raise item if item.is_a?(Exception)

    item.respond_to?(:call) ? item.call(request) : item
  end

  # The requests driven so far, in order.
  def requests = @calls.map(&:first)

  # The Authorization values sent on each drive: nil when the drive carried none.
  def authorization_headers
    requests.map { |request| request.headers["Authorization"]&.first }
  end
end
