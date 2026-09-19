# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # REDIR-6's clear error: a re-send site was asked to send a request whose body is present
  # and not replayable, and refused rather than corrupt or truncate the re-send. Raised by
  # Dexpace::Redirect::Step before a method-preserving redirect is followed (the 303 GET rebuild
  # is exempt, having no body to re-send); the message names replayability by word, as the
  # requirement asks. A StandardError including Dexpace::Error, flat under Dexpace:: on the
  # tree's one-error-per-file convention and 6a's P6-56 precedent for this namespace
  # (RetryPredicateError) -- the design named it Dexpace::Resilience::NotReplayableError, and
  # phase 6b's checklist records the move.
  class NotReplayableError < ::StandardError
    include Dexpace::Error

    # @param context [String] what was being re-sent, named in the message
    def initialize(context)
      super("#{context} cannot be re-sent: the request body is present and not replayable " \
            "(REDIR-6)")
    end
  end
end
