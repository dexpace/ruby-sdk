# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # Raised when a caller supplies an argument no model can accept: a missing required field
  # (HTTP-4, in SEAM-29's "<name> is required" form), a malformed URL (HTTP-47), a header name
  # carrying a control byte (HTTP-17).
  #
  # It subclasses Ruby's own ArgumentError because that is what the failure IS -- a caller
  # mistake, which the styleguide raises from validation helpers and never rescues in ordinary
  # flow. The SDK-specific name is InvalidArgumentError, never Dexpace::ArgumentError: the latter
  # would shadow ::ArgumentError for every file inside `module Dexpace`, so a bare
  # `rescue ArgumentError` in core would silently stop catching Ruby's.
  #
  # The rule for when core converts a stdlib exception into this one, fixed here because every
  # later factory decides it again otherwise: a public factory or coercion that raises a stdlib
  # exception BECAUSE OF the argument it was given rescues it and re-raises this class naming the
  # argument, in SEAM-29's message form, with the original left as the `cause` (URL.parse! is the
  # phase-1 example). A factory that can pre-empt the stdlib exception -- a byte check before a
  # case fold, an Integer check before a range test -- does that instead and adds no rescue
  # (Status.of, Method.of, Protocol.parse).
  class InvalidArgumentError < ::ArgumentError
    include Dexpace::Error
  end
end
