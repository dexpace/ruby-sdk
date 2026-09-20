# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A transport double for testing an ASSERTION's own logic against a known-good and a known-bad
# send, independent of any real adapter. `on_call` receives (request, options, cancellation) and
# returns whatever the test wants adapted into a Dexpace::Response, or raises. The gem's own
# double, never a lift of dexpace-core's FakeTransport (8a's design, "Work phase 8a postponed").
class StubTransport
  attr_reader :calls

  def initialize(&on_call)
    @on_call = on_call
    @calls = []
    @closed = false
  end

  def call(request, options, cancellation)
    @calls << [request, options, cancellation]
    @on_call.call(request, options, cancellation)
  end

  def close
    @closed = true
    nil
  end

  def closed?
    @closed
  end

  def owned?
    true
  end
end
