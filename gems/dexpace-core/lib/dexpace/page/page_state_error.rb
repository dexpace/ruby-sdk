# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"
require_relative "../page"

module Dexpace
  class Page
    # PAGE-14's "re-iteration MUST fail rather than silently restart": the error a second #each
    # on a single-use Pages view raises. A STATE error and never Dexpace::InvalidArgumentError --
    # no argument is involved, the object was simply used twice -- so a caller rescuing
    # ArgumentError around a page loop does not catch it, and it sits in the same family as the
    # SSE facade's state error for the identical single-use latch (phase 10's inbound bullet of
    # 2026-09-13 on PAGE-14 and SSE-26; P7-103). A StandardError including Dexpace::Error, like
    # every namespaced error since phase 6c; a shared core supertype for the two subsystems' state
    # errors is a pure widening phase 10 can insert.
    class PageStateError < ::StandardError
      include Dexpace::Error
    end
  end
end
