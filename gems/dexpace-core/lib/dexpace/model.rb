# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/invalid_argument_error"

module Dexpace
  # The construction contract every core value type includes.
  #
  # Four operations, kept in one place because each of them is a rule that is otherwise remembered
  # per type: the field-named failure SEAM-29 fixes, the derivation that re-validates, and the two
  # ways a model takes ownership of something a caller handed it.
  module Model
    # HTTP-4 and SEAM-29: one helper, one error class, one message form, so a required-field
    # failure cannot be phrased differently by two models.
    def self.required!(name, value)
      raise InvalidArgumentError, "#{name} is required" if value.nil?

      value
    end

    # HTTP-5 and XCUT-15: the model owns its collections outright.
    #
    # `copy: true` is load-bearing. Ractor.make_shareable deep-freezes IN PLACE, and `dup` is
    # shallow, so make_shareable(hash.dup) would freeze the caller's live value arrays. With
    # copy: true the caller's object graph is untouched and the returned copy is deep-frozen,
    # which is what lets every accessor return the same frozen reference with no per-access
    # wrapper (design §4, §10.11).
    #
    # Two things make_shareable cannot copy, both answered here rather than escaping as Ruby's own
    # error outside `rescue Dexpace::Error` (phase 10, phase 1's review R3-1). A Hash's DEFAULT PROC
    # is behaviour, not data -- `Hash.new { ... }` made make_shareable raise TypeError ("allocator
    # undefined for Proc") on every supported Ruby -- so a model's copy drops it: what the model
    # owns is the entries the caller handed it, and a lookup miss on the model answers nil, as on
    # any other model collection. Anything else that cannot be made shareable (a Proc or a Mutex
    # among the values) is the SDK's argument error naming what was refused.
    def self.own(collection)
      owned = collection #: untyped
      if owned.is_a?(::Hash) && owned.default_proc
        owned = owned.dup
        owned.default_proc = nil
      end
      Ractor.make_shareable(owned, copy: true)
    rescue ::TypeError, ::Ractor::Error => error
      raise InvalidArgumentError, "a model cannot own this collection: #{error.message}"
    end

    # A String a caller still holds a reference to is externally-mutable state XCUT-15 forbids a
    # model from aliasing.
    def self.frozen_string(value)
      value.frozen? ? value : value.dup.freeze
    end

    # HTTP-3's derivation for a type with no builder.
    #
    # This overrides Data#with deliberately. Verified on three interpreters: Data#with does not
    # call an `initialize` override on Ruby 3.2.11, and does on 3.4.10 and 4.0.6 -- so the
    # inherited method skips every HTTP-4/SEAM-29 check on the declared floor while passing on the
    # developer's Ruby. Routing through the type's own .build makes derivation uniform, and every
    # type gets it by including this module rather than by remembering.
    #
    # The parameter is a positional Hash rather than a `**` splat, and the call shape is the same:
    # Ruby passes keywords to a method that declares none as one positional Hash, on every Ruby
    # in the supported range. A splat allocates a Hash even on the empty call, which is what
    # Dexpace/NoKeywordSplat forbids on a public library method; this form allocates nothing when
    # nothing changes and only what the caller passed otherwise. What the splat form would have
    # refused at the call site -- a positional that is not a Hash -- is refused here with the
    # SDK's error, so it cannot escape as a NoMethodError from reading `empty?` off it.
    def with(changes = nil)
      return self if changes.nil?
      raise InvalidArgumentError, "with takes a Hash of member changes" unless changes.is_a?(Hash)
      return self if changes.empty?

      self.class.build(**to_h, **changes)
    end
  end
end
