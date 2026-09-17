# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# OBS-10 and OBS-23's two key names and OBS-10's default allow-list, as phase 5c ships them early
# for phase 5b to adopt (P5-71). The file holds exactly three constants and requires nothing, so
# tracing.rb and scope.rb can require it without dragging the logging half in (R11, Task 11).
class DexpaceInstrumentationDiagnosticsTest < DexpaceTestCase
  Diagnostics = Dexpace::Instrumentation::Diagnostics

  SOURCE = File.expand_path("../../../lib/dexpace/instrumentation/diagnostics.rb", __dir__)

  test "OBS-23: the two keys are the wire names as Symbols" do
    assert_equal(:"trace.id", Diagnostics::TRACE_ID)
    assert_equal(:"span.id", Diagnostics::SPAN_ID)
  end

  test "OBS-10: the default allow-list is exactly {trace.id, span.id}, frozen, in that order" do
    assert_equal(%i[trace.id span.id], Diagnostics::DEFAULT_KEYS)
    assert_predicate(Diagnostics::DEFAULT_KEYS, :frozen?)
    assert_same(Diagnostics::TRACE_ID, Diagnostics::DEFAULT_KEYS[0])
    assert_same(Diagnostics::SPAN_ID, Diagnostics::DEFAULT_KEYS[1])
  end

  # P5-71: 5c ships the three constants and nothing else of 5b's -- no method, no Event, no
  # Keys -- and the file requires nothing, which is what keeps Task 11's load-time assertion
  # true. The source scan is the assertion phase 5b's Task 6 must keep true when it extends
  # the file: a require of anything else in 5b would pull the logging half in behind Tracing.
  test "P5-71: the module defines three constants, no method, and the file requires nothing" do
    assert_equal(%i[DEFAULT_KEYS SPAN_ID TRACE_ID], Diagnostics.constants(false).sort)
    assert_empty(Diagnostics.singleton_methods)
    assert_empty(Diagnostics.instance_methods(false))
    refute_match(/^\s*require/, File.read(SOURCE), "diagnostics.rb must require nothing")
  end

  # The Symbol decision (R11) rests on a carrier fact the corpus records for 3.4.10 only:
  # Fiber[]= interns a String key there and on 4.0.6, but raises TypeError on 3.2.11 and 3.3.12
  # (measured 2026-09-17). A Symbol works on every row, and this is the row-by-row proof.
  test "R11: a Symbol key is accepted by the per-key carrier API on this interpreter" do
    ::Fiber[Diagnostics::TRACE_ID] = "t"

    assert_equal("t", ::Fiber[Diagnostics::TRACE_ID])
    assert_equal(:"trace.id", ::Fiber.current.storage.keys.find { |k| k == :"trace.id" })
  ensure
    ::Fiber[Diagnostics::TRACE_ID] = nil
  end
end
