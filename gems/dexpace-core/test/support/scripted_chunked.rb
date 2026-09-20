# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Design §10.2's canonical body representation with a SCRIPT: an object responding to #each whose
# entries are String chunks or Exceptions, yielding a String and RAISING an Exception where one
# sits (FakeSource's own convention), and counting the entries it reached in `yielded`. Under
# Dexpace::IO::BufferedSource.over it is phase 7b's mid-stream failure -- SSE-29, SSE-36 and
# SSE-40's "propagates a read failure at the offending pull" -- delivering every byte before the
# Exception entry and raising from the pull that reaches it; with one event's bytes per String
# entry it is also SSE-39's read-ahead counter, beside 3a's FakeChunked. It replaces the plan's
# `ByteSource.failing_after` and `CountingBody`, which the tree never had.
#
# One fact a suite must not assert against it: after the Exception escapes, the BufferedSource's
# enumerator is a dead fiber, and Enumerator#next on a dead fiber RESTARTS #each from its first
# entry -- so a further pull re-delivers the first chunk's bytes rather than nil or a second
# raise (measured on 3.2.11, 3.3.12, 3.4.10 and 4.0.6; `sse/matrix_facts_test.rb`). The facade
# never pulls again because it closed itself first (SSE-27's closed? check runs before the read).
class ScriptedChunked
  attr_reader :yielded

  def initialize(*script)
    @script = script
    @yielded = 0
  end

  def each
    @script.each do |entry|
      @yielded += 1
      raise entry if entry.is_a?(::Exception)

      yield entry
    end
  end
end
