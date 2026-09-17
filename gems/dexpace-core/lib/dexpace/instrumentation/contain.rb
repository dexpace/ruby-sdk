# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error/invalid_argument_error"
require_relative "severity"
require_relative "keys"
require_relative "logger"

# Instrumentation.contain and .diagnostic live in their own file: they are functions on the
# namespace and not members of Logger or Event (P5-37), and module-organization/1828a984 counts
# constants -- this file adds two functions and no constant.
module Dexpace
  # The instrumentation subsystem: design §8.1's namespace, which phase 4a opened with the
  # bundle and the no-op singletons, phase 5c filled with the tracing and metrics half, and phase
  # 5b filled with the logging half. This file adds its two module functions.
  module Instrumentation
    # OBS-20 and XCUT-20: the one failure-containment primitive. "Emitting structured log events
    # around a request MUST NOT be able to fail the request": every log-emission site -- the
    # request event, the response event, the failure event, the body drain that feeds them, and
    # the three diagnostics phases 2 and 5a left for this facade -- runs inside this, so a
    # StandardError raised there becomes a best-effort `http.instrumentation.*` diagnostic at
    # WARNING carrying the error as its cause, and a failure while emitting THAT is swallowed
    # with no second attempt, no Kernel#warn and no counter: a swallow path with its own failure
    # mode is a third failure mode.
    #
    # It returns nil and discards the block's value, so no call site can branch on whether
    # logging worked, and it is a module function and not a method on Logger or Event (P5-37):
    # `logger.contain { }` reads as "the logger contains", which invites the containment to move
    # to the sink, the placement §8.1 rejects for redaction for the same reason -- it can be
    # bypassed by installing a different sink.
    #
    # It wraps log-emission sites and NOTHING else. Tracer, scope and meter calls are deliberately
    # outside it (boundary 3): OBS-20's own words are "the runtime does NOT defensively wrap"
    # them, their guarantee is OBS-30's contract on the implementer, and a throwing tracer or
    # meter WILL propagate and can fail the request. Only StandardError is rescued: a
    # SignalException, a NoMemoryError or a ScriptError inside a log line is not a logging
    # failure, and Dexpace/NoThreadInterrupt is why no asynchronous interrupt can land between
    # the rescue and the diagnostic.
    #
    # @param logger [Logger] the facade the diagnostic goes through; Logger::NULL contains and
    #   reports nothing
    # @param event [String] the diagnostic's event name, one of the `http.instrumentation.*`
    #   constants on Events
    # @yield the log-emission site
    # @return [nil] always
    # @raise [Dexpace::InvalidArgumentError] without a block -- a programmer error, refused
    #   before the rescue region so it cannot be mistaken for a contained failure
    def self.contain(logger, event:)
      raise InvalidArgumentError, "contain requires a block" unless block_given?

      begin
        yield
      rescue ::StandardError => error
        report(logger, event, error)
      end
      nil
    end

    # One contained `http.instrumentation.*` diagnostic at WARNING -- the shape the three
    # wirings phase 5b landed share (P5-92): Dexpace.close_quietly's close route, Hooks.notify's
    # dropped-failure route and the proxy resolver's configuration warning, and the shape phase
    # 8b's shutdown event will take. The emission runs inside .contain under
    # Events::INSTRUMENTATION_LOG, so a sink that raises while reporting a close failure
    # produces a log-site diagnostic and never a raise, and a failure of THAT is swallowed.
    #
    # @param logger [Logger] the facade; Logger::NULL emits nothing
    # @param event [String] the diagnostic's event name, one of the constants on Events
    # @param cause [Exception, nil] the failure being reported, attached through Event#cause
    # @param message [String, nil] free text, under Keys::MESSAGE, for a diagnostic with no
    #   throwable (the configuration warning)
    # @return [nil] always
    def self.diagnostic(logger, event:, cause: nil, message: nil)
      contain(logger, event: Events::INSTRUMENTATION_LOG) do
        emitted = logger.event(Severity::WARNING).event(event).cause(cause)
        emitted.field(Keys::MESSAGE, message) unless message.nil?
        emitted.emit
      end
    end

    # The diagnostic emission, itself a log-emission site: a failure here is swallowed with no
    # second attempt.
    def self.report(logger, event, error)
      logger.event(Severity::WARNING).event(event).cause(error).emit
    rescue ::StandardError
      # OBS-20: "a secondary failure while emitting that diagnostic MUST be swallowed".
      nil
    end
    private_class_method :report
  end
end
