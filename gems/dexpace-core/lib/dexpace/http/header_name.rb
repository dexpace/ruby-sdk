# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "header_syntax"

module Dexpace
  # A header name that compares by its case-folded form and emits its original casing (HTTP-21).
  #
  # ONE member, the original casing. The fold is derived from it at construction and exposed as
  # #folded, for the reason Status keeps its canonical name out of its members: a derived value
  # that is also a member can be handed in stale -- `#with(original: "Content-Type")` carries the
  # old fold in `to_h` -- and would have to be accepted and ignored. Setting it before `super`
  # is the one moment a Data instance is still mutable, and it is what makes Model#with's route
  # through `.build` load-bearing on Ruby 3.2, where the inherited Data#with never runs this
  # constructor and would leave the fold unset.
  #
  # HTTP-22's process-wide interning is a MAY and is not built: the observable contract is value
  # equality by folded name, which this type gives without it.
  class HeaderName < Data.define(:original)
    include Model

    private_class_method :new

    # The case-folded name: HTTP-13's key for lookup, containment, equality and hashing.
    attr_reader :folded

    # The validating factory every construction path goes through.
    def self.build(original:)
      new(original: original)
    end

    # A String or a HeaderName, so every string-keyed Headers method interoperates with the typed
    # one at no cost when the caller already has the type.
    def self.of(name)
      return name if name.is_a?(HeaderName)

      build(original: name)
    end

    # The validating constructor. HTTP-13's fold is `downcase` with NO argument, ever: Ruby's fold
    # is opt-in-locale -- "I".downcase(:turkic) is "ı" -- and the repository-wide cop rejects the
    # argument form, so the ASCII/invariant guarantee is enforced rather than assumed. The fold
    # never meets a non-ASCII byte anyway, because validate_name! rejected one first; relaxing
    # HTTP-17 would therefore break HTTP-13, which is why that dependency is stated here. Nor
    # does it meet a tag Ruby cannot fold under: validate_name! hands back the proven bytes under
    # an ASCII-compatible tag, so a stateful-encoding name folds instead of crashing.
    def initialize(original:)
      Model.required!("header name", original)
      raise InvalidArgumentError, "header name must be a String" unless original.is_a?(String)

      trimmed = HeaderSyntax.validate_name!(original)
      @folded = trimmed.downcase.freeze
      super(original: Model.frozen_string(trimmed))
    end

    # The original casing, for wire emission.
    def to_s
      original
    end

    # Data generates equality over the original casing, which would make "Accept" and "accept"
    # unequal and violate HTTP-21. Folded-only comparison is the observable contract; the
    # original casing is carried for emission and takes no part in it (api-design/e4fa3438
    # permits the override with this comment).
    def ==(other)
      other.is_a?(HeaderName) && folded == other.folded
    end
    alias eql? ==

    # Agrees with #==: two casings of one name share a Hash slot.
    def hash
      folded.hash
    end
  end
end
