# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A real in-memory _Sink for SEAM-25's one-event assertion and P8-22's worker diagnostic: the
# four writers and the four predicates, every rendered payload kept in order. Shaped like core's
# RecordingSink and declared fresh here under a gem-unique name, because `rake test:gems` loads
# every gem's suite into ONE `ruby -w` process in which core's `RecordingSink::Entry` already
# exists, and a second `Entry =` under the same name is the "already initialized constant"
# warning NFR-6 makes fatal at load (8a's checklist, departure 35: its double is
# NetHTTPRecordingSink for the same reason).
class PoolRecordingSink
  # One recorded call: the severity method, the positional message and the payload (the block's
  # value, or the message when there was none).
  Entry = ::Data.define(:severity, :message, :payload)

  def initialize
    @entries = []
    @mutex = ::Thread::Mutex.new
  end

  # A copy, read under the mutex the emitting threads write under.
  def entries
    @mutex.synchronize { @entries.dup }
  end

  # The entries carrying `event` under the facade's event key, in order.
  def events_named(event)
    entries.select do |entry|
      entry.payload.is_a?(::Hash) && entry.payload[Dexpace::Instrumentation::Keys::EVENT] == event
    end
  end

  def debug(message = nil, &) = record(:debug, message, &)
  def info(message = nil, &) = record(:info, message, &)
  def warn(message = nil, &) = record(:warn, message, &)
  def error(message = nil, &) = record(:error, message, &)

  def debug? = true
  def info? = true
  def warn? = true
  def error? = true

  private

  # The block is evaluated outside the mutex, like a real sink.
  def record(severity, message)
    payload = block_given? ? yield : message
    entry = Entry.new(severity: severity, message: message, payload: payload)
    @mutex.synchronize { @entries << entry }
    nil
  end
end
