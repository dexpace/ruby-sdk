# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A real in-memory _Sink -- the duck type §8.1 fixes as the stdlib Logger surface as a structural
# subset: #debug/#info/#warn/#error, each taking a message OR a block, and the four predicates.
# It is deliberately NOT the stdlib Logger: `require "logger"` is refused by name in this gem's
# lib/ AND its test/ (the require scan reads text), so the one legitimate proof that a real
# Logger satisfies the type is dexpace-conformance's (phase 8a), where a declared dependency is
# permitted. A fake by testing/7ecef8e8's definition: enablement is set per severity by the
# test, and every rendered payload is kept in order, which is what every OBS-1..OBS-9, OBS-39
# and OBS-40 assertion reads.
#
# Top level, not under Dexpace: twenty-four of the tree's twenty-seven support files are
# (FakeTransport, FakeClock, FakeConfigSource, RecordingBody); 5c's seven are namespaced only
# because 5b's plan consumed them by those names (P5-73). The plan's own "flat under Dexpace, on
# 5a's FakeClock precedent" was written before 5a went top level (P5-58); the checklist records
# the choice. It lives in dexpace-core's test tree and is not public API.
class RecordingSink
  # One recorded call: the severity method that was called, the positional message (nil under
  # the block form) and the payload -- the block's value, or the message when there was none.
  Entry = ::Data.define(:severity, :message, :payload)

  attr_accessor :debug_enabled, :info_enabled, :warn_enabled, :error_enabled
  attr_reader :entries

  def initialize(debug_enabled: true, info_enabled: true, warn_enabled: true, error_enabled: true)
    @debug_enabled = debug_enabled
    @info_enabled = info_enabled
    @warn_enabled = warn_enabled
    @error_enabled = error_enabled
    @entries = []
    @mutex = ::Thread::Mutex.new
  end

  def debug(message = nil, &) = record(:debug, message, &)
  def info(message = nil, &) = record(:info, message, &)
  def warn(message = nil, &) = record(:warn, message, &)
  def error(message = nil, &) = record(:error, message, &)

  def debug? = @debug_enabled
  def info? = @info_enabled
  def warn? = @warn_enabled
  def error? = @error_enabled

  # The payloads alone, in order.
  def payloads = @entries.map(&:payload)

  def clear
    @mutex.synchronize { @entries.clear }
    nil
  end

  private

  # The block is evaluated outside the mutex, like a real sink, so a payload whose rendering
  # re-enters this sink (a hostile #to_s that logs) cannot deadlock the recorder.
  def record(severity, message)
    payload = block_given? ? yield : message
    entry = Entry.new(severity: severity, message: message, payload: payload)
    @mutex.synchronize { @entries << entry }
    nil
  end
end
