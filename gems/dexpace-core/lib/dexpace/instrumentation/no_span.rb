# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # CTX-15's no-op span, the object behind NO_SPAN. Responds to nothing beyond Object's own
    # surface: phase 4 fixes the slot and the identity of the object filling it; OBS-21 and
    # OBS-25 fix the protocol, and that is phase 5's (5c, Tasks 3-5), which gives THIS class its
    # methods rather than introducing a second no-op span -- the class is a private_constant and
    # so not NFR-4-locked, while the object keeps the identity phase 4 published.
    class NoSpan; end # rubocop:disable Lint/EmptyClass -- postponed protocol: phase 5c adds it.
    private_constant :NoSpan

    # The one shared, frozen no-op span every untraced bundle carries (CTX-14's "an active span",
    # CTX-15). One instance, so OBS-25's "MUST NOT allocate per call" is assertable by reference
    # identity: `assert_same Dexpace::Instrumentation::NO_SPAN, bundle.span`. Public, where
    # BoundedMap is not, because that assertion is a QUALIFIED reference and a qualified reference
    # to a private constant raises even from inside Dexpace (design, verified fact 6).
    NO_SPAN = NoSpan.new.freeze
  end
end
