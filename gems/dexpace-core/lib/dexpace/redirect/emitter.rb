# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../http/url"
require_relative "../instrumentation/contain"
require_relative "../instrumentation/keys"
require_relative "../instrumentation/logger"
require_relative "../instrumentation/redactor"
require_relative "../instrumentation/severity"
require_relative "events"

module Dexpace
  module Redirect
    # REDIR-28's emission site, split out of Step the way 5b's Emitter is split out of its step:
    # one object owning every `logger.event(...)` call, every field key and every redaction the
    # redirect layer performs, so Step reads as the follower and this reads as the record.
    #
    # Every emission runs inside Instrumentation.contain, so a raising sink cannot fail a
    # redirect (OBS-20, XCUT-20). Every URL-valued field goes through the LOGGER's redactor --
    # `logger.redactor`, P5-95's one policy per logging path; Step takes no `redactor:` keyword
    # of its own -- by name, at construction of the record, because Keys::FROM_URL and
    # Keys::TO_URL are not Instrumentation::Keys::URL_FULL and 5b's structural table does not
    # reach them (R8). A redactor is a caller's object (`Logger.build(redactor:)`) and is not
    # guaranteed total the way Redactor::DEFAULT is, so #redacted degrades a raise to the
    # MALFORMED_URL placeholder rather than dropping the record: REDIR-28's "redaction failures
    # degrading to a placeholder rather than crashing logging". The one exception is REDIR-28's
    # own: the malformed-Location record carries the raw header value under Keys::LOCATION_RAW,
    # untouched, because it failed to parse and therefore cannot be redacted.
    #
    # A private_constant with a sig/ mirror, asserted through Step's suite; not public API.
    class Emitter
      def initialize(logger)
        @logger = logger
      end

      # One followed hop (INFO): from, to, the status and the count so far.
      def hop(from:, to:, status:, redirect_count:)
        contained do
          event = @logger.event(Instrumentation::Severity::INFO).event(Events::HOP_FOLLOWED)
          event.field(Keys::FROM_URL, redacted(from)).field(Keys::TO_URL, redacted(to))
          event.field(Instrumentation::Keys::HTTP_RESPONSE_STATUS_CODE, status.code)
          event.field(Keys::REDIRECT_COUNT, redirect_count).emit
        end
      end

      # REDIR-16 (WARNING): the resolved target was already visited.
      def loop_detected(from:, to:, redirect_count:)
        contained do
          event = @logger.event(Instrumentation::Severity::WARNING).event(Events::LOOP_DETECTED)
          event.field(Keys::FROM_URL, redacted(from)).field(Keys::TO_URL, redacted(to))
          event.field(Keys::REDIRECT_COUNT, redirect_count).emit
        end
      end

      # REDIR-15 (WARNING): the downgrade, under the name of the outcome it actually had.
      def scheme_downgrade(from:, to:, permitted:)
        name = permitted ? Events::SCHEME_DOWNGRADE_PERMITTED : Events::SCHEME_DOWNGRADE_REJECTED
        contained do
          event = @logger.event(Instrumentation::Severity::WARNING).event(name)
          event.field(Keys::FROM_URL, redacted(from)).field(Keys::TO_URL, redacted(to)).emit
        end
      end

      # REDIR-18 (WARNING): the raw value, NOT redacted, with the parser's error as the cause.
      def location_malformed(raw:, error:)
        contained do
          event = @logger.event(Instrumentation::Severity::WARNING).event(Events::LOCATION_MALFORMED)
          event.field(Keys::LOCATION_RAW, raw).cause(error).emit
        end
      end

      private

      def contained(&)
        Instrumentation.contain(@logger, event: Instrumentation::Events::INSTRUMENTATION_LOG, &)
      end

      # The logger's redactor over the external form, total: a caller-supplied redactor that
      # raises yields the placeholder, and the record is still emitted.
      def redacted(uri)
        @logger.redactor.url(URL.external_form(uri))
      rescue ::StandardError
        Instrumentation::Redactor::MALFORMED_URL
      end
    end
    private_constant :Emitter
  end
end
