# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "suppressible"

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
  # Dexpace.attach_suppressed -- arrived with phase 4b, and it lives on Dexpace::Suppressible
  # rather than here (P4-12): the trail has to be attachable to a caller's exception, which means
  # extending that object with a module, and extending a third-party error with THIS module would
  # make `rescue Dexpace::Error` catch errors the SDK never raised. Including Suppressible gives
  # every SDK error the trail; `rescue Dexpace::Error` keeps meaning "the SDK raised this".
  #
  # `suppressible.rb` requires nothing and this file requires it, in that order and never the
  # reverse: the `include` below needs the constant at load, and a require from suppressible.rb
  # back to any error class would re-enter this file before its body has run.
  module Error
    include Dexpace::Suppressible
  end
end
