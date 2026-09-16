# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised for every composition-time or defect condition in the stage pipeline (design §5.1;
  # P4-37): a distinct second step on an occupied pillar (PIPE-5), an install at the terminal
  # SEND stage (PIPE-8), a cursor driven twice or forked after its drive (PIPE-15), a fork from a
  # slot stage, a cross-stage surgical move (PIPE-18, PIPE-19), a missing anchor (PIPE-21), a
  # rejected bulk reload (PIPE-23), a rejected preset (PIPE-24), and R10's two stage-assignment
  # rejections.
  #
  # One class carrying no fields, deliberately. Every one of those conditions is fixed by editing
  # the code that composed the pipeline; no caller branches on the reason at run time, so a
  # carried field would be NFR-4-locked surface with no reader. The contrast with a runtime
  # conflict a caller may retry -- which does carry what the retry needs -- is the point. PIPE-5's
  # "name both step types" and PIPE-21's "identify the missing type" are message requirements and
  # are met in the message, whose forms the phase plan fixes so the suites assert exact text at
  # the site that raises it.
  #
  # A StandardError including Dexpace::Error, like every SDK failure (phase 1's P1-2): not a
  # Dexpace::InvalidArgumentError, because a composition defect is not a bad argument to one
  # method but a wrong shape for the whole runtime.
  class PipelineError < ::StandardError
    include Dexpace::Error
  end
end
