# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "registry"
require_relative "serde/error"
require_relative "serde/serialization_error"
require_relative "serde/deserialization_error"

module Dexpace
  # The wire-codec seam: a duck type of six methods, a .conforms? predicate and an RBS interface.
  #
  #   #media_type                        the media type this serializer produces (SEAM-19)
  #   #dump_string(value)                a fresh String                          (SEAM-20)
  #   #dump_bytes(value)                 a fresh Encoding::BINARY String         (SEAM-20)
  #   #dump_to(value, sink)              writes into a caller-owned #write sink; never closes it
  #   #dump_into(value, buffer, offset:) writes at an offset; IndexError on overflow
  #   #load(source, witness)             reads to EOF; never closes the source   (SEAM-21)
  #
  # All four of SEAM-20's allocation profiles ship and two of them are one Ruby type: a String
  # tagged Encoding::BINARY *is* Ruby's byte array, so #dump_bytes differs from #dump_string only
  # in the encoding tag -- which is the whole of the distinction the requirement draws (§10.13).
  # Both ship because the tag is load-bearing at §3.1's encoding boundary.
  #
  # #dump(value, sink) is design §3.4's shorthand for #dump_to and an adapter may define it, but it
  # is deliberately **not** in CONTRACT: a codec implementing the four named profiles conforms
  # without also defining an alias, and requiring the alias would make the shorthand mandatory,
  # which is the opposite of what a shorthand is.
  #
  # SEAM-19's undefaulted media type is enforced here rather than at the codec: .conforms? requires
  # #media_type and this module supplies no default and has no fallback constant, so a codec that
  # forgets it fails registration instead of silently stamping the wrong Content-Type. That the
  # value is *correct* is phase 7's.
  #
  # SEAM-22's reflective generic type capture is replaced by the witness protocol (§10.14, §7.3,
  # phase 7). The clause that survives the substitution is fixed here: #load takes an explicit
  # witness and there is no witness-less overload to fall into.
  #
  # Inside this namespace a bare `JSON` is Dexpace::Serde::JSON once dexpace-serde-json is loaded,
  # the same hazard Dexpace::Async carries for `Thread`; Dexpace/QualifiedCoreConstant enforces the
  # ::-qualified spelling on every file under lib/dexpace/serde/.
  module Serde
    CONTRACT = %i[media_type dump_string dump_bytes dump_to dump_into load].freeze
    private_constant :CONTRACT

    REGISTRY = Registry.new(
      seam: "codec",
      installer: "Dexpace::Serde.install",
      conforms: ->(object) { Dexpace::Serde.conforms?(object) },
    )
    private_constant :REGISTRY

    class << self
      # The runtime half of the seam: every one of the six methods answered.
      def conforms?(object) = CONTRACT.all? { |name| object.respond_to?(name) }

      # The seam methods `object` does not answer, so a registration failure can name WHICH of
      # the six a codec forgot -- .conforms? returns a Boolean, and "does not implement the seam"
      # is the one message SEAM-19 most needs to be specific.
      #
      # @return [Array<Symbol>]
      def missing_methods(object) = CONTRACT.reject { |name| object.respond_to?(name) }

      # Require-time self-registration (design §3.6), with the version-skew guard on `core:`.
      def register(key, factory, core:)
        REGISTRY.register(key, factory, core: core)
        self
      end

      # SEAM-5's explicit install, which always wins over a registered factory.
      def install(codec)
        REGISTRY.install(codec)
        self
      end

      # The resolved codec (SEAM-5, SEAM-7).
      def resolve = REGISTRY.resolve

      # The keys every required codec gem registered under.
      def registered_keys = REGISTRY.registered_keys

      # SEAM-6's test-scoped override: block-scoped, unchecked, restored afterwards.
      def swap(codec, &) = REGISTRY.swap(codec, &)
    end
  end
end
