# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# 8b's own #call(request, options, cancellation)-shaped double (SEAM-11/SEAM-16), independent of
# gems/dexpace-core/test/support/fake_transport.rb: this gem's test_helper.rb puts only its own
# lib on the load path, and a require_relative into another gem's test/ tree is the cross-gem
# reach styleguide 12.6 forbids. Top level and named for its gem, because `rake test:gems` loads
# every gem's suite into ONE process in which core's bare `FakeTransport` already exists (8a's
# checklist, departure 35).
#
# Modes: `gate:` a ::Thread::Queue the test controls, so #call blocks until the test pushes rather
# than sleeping; `entered:` a ::Thread::Queue this double pushes to as its FIRST act, so a test
# that must act only once the worker is inside #call waits on a condition instead of a sleep --
# every "window" assertion in the bridge suite gates on it, because AsyncOver checks the token
# BEFORE dispatch as well as after and a cancel that lands before the worker reaches #call never
# reaches the transport at all; `response:`/`raises:` what #call produces once the gate opens.
#
# `ignores_cancellation:` is documentary only and changes no behaviour: #call never inspects its
# own `cancellation` argument in ANY mode, exactly like Net::HTTP itself (a real transport has to
# be told to close its socket under a blocked read; it does not poll a token). The keyword exists
# so ASYNC-7's test can name its own intent at the call site. The third argument is still recorded
# in `calls` either way, so a test can assert what was threaded through.
class PoolFakeTransport
  def initialize(response: nil, raises: nil, gate: nil, entered: nil, ignores_cancellation: false)
    @response = response
    @raises = raises
    @gate = gate
    @entered = entered
    @ignores_cancellation = ignores_cancellation
    @calls = []
    @mutex = ::Thread::Mutex.new
  end

  def call(request, options, cancellation)
    @mutex.synchronize { @calls << [request, options, cancellation] }
    @entered&.push(:in_call)
    @gate&.pop
    raise @raises if @raises

    @response
  end

  # A copy, read under the same mutex the worker writes under.
  def calls
    @mutex.synchronize { @calls.dup }
  end

  def ignores_cancellation? = @ignores_cancellation
end
