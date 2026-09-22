# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A logging sink that records every write, for the tests that assert what the adapter logs. The
# gem's own double: core's test support is not reachable from an adapter gem's suite, and a
# double this small is not worth a shared home. Every method the facade's duck-typed `_Sink`
# names, and nothing else -- the shape phase 8a's NetHTTPRecordingSink fixed.
#
# Named for its gem, never a bare `RecordingSink`: `test:gems` loads every gem's suite into ONE
# process (tools/suite_runner.rb, so SimpleCov reports one aggregate figure), and core's
# test/support/recording_sink.rb already defines a top-level `RecordingSink` with an `Entry` of its
# own -- a second definition re-assigns the constant, and that "already initialized constant"
# warning is fatal under NFR-6 at load time, before a single test runs.
class AsyncHTTPRecordingSink
  Entry = ::Data.define(:severity, :payload)

  attr_reader :entries

  def initialize
    @entries = []
    @mutex = ::Thread::Mutex.new
  end

  def debug(message = nil, &) = record(:debug, message, &)
  def info(message = nil, &) = record(:info, message, &)
  def warn(message = nil, &) = record(:warn, message, &)
  def error(message = nil, &) = record(:error, message, &)

  def debug? = true
  def info? = true
  def warn? = true
  def error? = true

  # The records whose event field is the given name.
  def events(name)
    @mutex.synchronize do
      @entries.select { |entry| entry.payload.is_a?(::Hash) && entry.payload["event"] == name }
    end
  end

  # The severities, in order, of every record under the given event name.
  def severities(name)
    events(name).map(&:severity)
  end

  private

  def record(severity, message)
    payload = block_given? ? yield : message
    @mutex.synchronize { @entries << Entry.new(severity: severity, payload: payload) }
    nil
  end
end
