# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A scriptable Dexpace::Transport double (phase 2's duck type, SEAM-11), phase 6a's: where
# FakeTransport answers ONE response or raise for every call, this one consumes a script -- one
# entry per call, in order -- so a retry suite can stage a 503, 503, 200 sequence (RECOV-19,
# RETRY-36) or a run of throwables (RETRY-34). Each entry is consumed once: a callable is
# invoked with (request, options, cancellation) and its answer used; an Exception instance is
# raised; anything else is returned as it is. A call past the end of the script raises, so a
# driver that sends once too often fails loudly rather than reading nil.
#
# #calls records every call's [request, options, cancellation] triple, frozen, so a test can
# assert the SAME request object was re-sent every time (RETRY-44, RECOV-19) with assert_same.
# `def call(request, options, cancellation)` with three positionals is what keeps
# Registry.callable?(transport, arity: 3) true, which Recovery::Orchestrator.build checks.
#
# Not phase 2's FakeTransport, which seven suites and three other doubles require by name and
# shape and which stays exactly as it is; a new double under a new name (phase 6a's checklist,
# "Deviations from the plan"). Top level, like every double under test/support/ since phase 2.
class ScriptedTransport
  attr_reader :calls

  def initialize(script)
    @script = script.dup
    @calls = []
    @mutex = ::Thread::Mutex.new
  end

  def call(request, options, cancellation)
    entry = @mutex.synchronize do
      @calls << [request, options, cancellation].freeze
      raise "ScriptedTransport: script exhausted after #{@calls.size - 1} calls" if @script.empty?

      @script.shift
    end
    case entry
    when ::Exception then raise entry
    when ::Proc, ::Method then entry.call(request, options, cancellation)
    else entry
    end
  end

  # The script entries not yet consumed.
  def remaining = @mutex.synchronize { @script.size }
end
