# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # RETRY-40's well-typed abort: raised by the two stage-based retry drivers when a
  # caller-supplied `should_retry:` predicate itself raises. The predicate's own failure is
  # carried as #cause -- a genuine wrap of a fresh failure, raised with `cause:` at the site,
  # and not a re-raise of a carried error, so pipeline/7ce4431d's `cause: nil` rule does not
  # apply to it. A StandardError including Dexpace::Error, flat under Dexpace:: on the tree's
  # one-error-per-file convention (PipelineError, ContextConflictError, ProtocolError), and
  # numbered P6-11: RETRY-40 requires the well-typed error and names none.
  #
  # Only a predicate that raises a StandardError is wrapped. The fatal family -- NoMemoryError,
  # SystemStackError -- propagates through an absent rescue arm, unchanged and unwrapped
  # (RETRY-25, RETRY-40's "fatal errors rethrown unchanged").
  class RetryPredicateError < ::StandardError
    include Dexpace::Error
  end
end
