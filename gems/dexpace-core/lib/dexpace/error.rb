# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # The marker every error raised by this SDK carries.
  #
  # A module rather than a base class, and the choice is forced: XCUT-4 requires a transport error
  # to belong to the runtime's I/O-error family so existing I/O rescue sites keep matching, which
  # in Ruby means `Dexpace::TransportError < ::IOError`. Ruby has single inheritance, so a class
  # root would make that requirement unsatisfiable in phase 8. `rescue` matches with Module#===,
  # which is `is_a?`, so `rescue Dexpace::Error` catches every including class exactly as a base
  # class would.
  #
  # Design §5's suppressed-exception trail -- #suppressed, the #detailed_message override and
  # Dexpace.attach_suppressed -- lands in phase 4 with the recovery chain that is its first
  # caller (phase 4b, Task 1). It is deliberately absent rather than stubbed here.
  module Error
  end
end
