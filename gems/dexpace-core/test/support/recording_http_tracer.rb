# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../lib/dexpace/instrumentation/http_tracer"

module Dexpace
  # OBS-29's "conformant emitter": INCLUDES the vocabulary and overrides all eleven, appending
  # one frozen tuple per callback -- the name first, the arguments after -- so the ordering test
  # can assert sequence, adjacency and identity (P5-48). Including the module rather than
  # re-declaring the methods is what gives HTTPTracer a caller in the suite (R14) and what makes
  # a missing override a silent no-op rather than a NoMethodError, which is the property OBS-28's
  # "implementers override only what they need" is about. It lives in Task 8 and not Task 1
  # because the module does not exist before it. Not public API; see recording_span.rb for why
  # the doubles are namespaced.
  class RecordingHTTPTracer
    include Instrumentation::HTTPTracer

    attr_reader :events

    def initialize
      @events = []
    end

    def operation_started(context)
      @events << [:operation_started, context].freeze
      nil
    end

    def operation_succeeded(context, response)
      @events << [:operation_succeeded, context, response].freeze
      nil
    end

    def operation_failed(context, error)
      @events << [:operation_failed, context, error].freeze
      nil
    end

    def attempt_started(context, attempt)
      @events << [:attempt_started, context, attempt].freeze
      nil
    end

    def attempt_failed(context, error, next_delay)
      @events << [:attempt_failed, context, error, next_delay].freeze
      nil
    end

    def retries_exhausted(context, error)
      @events << [:retries_exhausted, context, error].freeze
      nil
    end

    def request_url_resolved(context, url)
      @events << [:request_url_resolved, context, url].freeze
      nil
    end

    def connection_acquired(context, host, port)
      @events << [:connection_acquired, context, host, port].freeze
      nil
    end

    def request_sent(context, byte_count)
      @events << [:request_sent, context, byte_count].freeze
      nil
    end

    def response_headers_received(context, status, headers)
      @events << [:response_headers_received, context, status, headers].freeze
      nil
    end

    def response_received(context, byte_count)
      @events << [:response_received, context, byte_count].freeze
      nil
    end
  end
end
