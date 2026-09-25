# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../builder"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "sources"

module Dexpace
  class Configuration
    # The mutable assembler for a Configuration (CFG-8, CFG-9, CFG-10, CFG-12, CFG-37): the
    # override map, the two seams, and #property, the only in-SDK way to populate the third tier.
    #
    # No mutex, by requirement (CFG-12): "Configuration builders SHOULD be usable single-threaded
    # only; the immutability guarantee applies to the built configuration, not to an in-progress
    # builder." Nobody adds one for symmetry with Dexpace.configure's.
    #
    # In its own file beside configuration.rb, as phase 1 files every builder (headers/builder.rb,
    # request/builder.rb); it reopens `class Configuration`, so configuration.rb requires it at
    # its foot and it never appears in lib/dexpace.rb.
    class Builder
      include Dexpace::Builder

      # The seeds go through #override and the seams through the same guard the setters use, so a
      # nil value or a blank key in the seed map and a nil or non-callable seam fail fast exactly
      # as they would through the setters (CFG-37): .new is public, and only the two in-SDK callers
      # -- Configuration.builder and #new_builder -- hand it an already-validated map.
      #
      # @param overrides [Hash] seed overrides, copied
      # @param env_source [#call] CFG-11's environment seam
      # @param property_source [#call, nil] an inherited property seam, or nil for none yet
      # @raise [Dexpace::InvalidArgumentError] on a seed map that is not a Hash, a seed with a nil
      #   or blank key or a nil value, or an environment seam that is nil or not callable (CFG-37)
      def initialize(overrides: {}, env_source: Sources::ENVIRONMENT, property_source: nil)
        Model.required!("overrides", overrides)
        unless overrides.is_a?(::Hash)
          raise InvalidArgumentError, "overrides must be a Hash, got #{overrides.class}"
        end

        @overrides = {} #: Hash[String, String]
        overrides.each { |key, value| override(key, value) }
        @env_source = source!("env_source", env_source)
        @property_source = property_source && source!("property_source", property_source)
        @properties = {} #: Hash[String, String]
        # An INHERITED seam does not count as installed. Only #property_source= sets this flag:
        # Dexpace.configure seeds its builder from the live slot, so treating the inherited seam
        # as explicit would make the SECOND configure that calls #property raise, and CFG-13's
        # slot is "last-write-wins replacement". CFG-9's "shared, not copied" is preserved in
        # #build, which passes an inherited seam through by reference whenever no #property was
        # added over it.
        @property_source_explicit = false
      end

      # Installs or replaces the override under the exact key (CFG-1's first tier).
      #
      # @return [self]
      # @raise [Dexpace::InvalidArgumentError] on a nil or blank key or a nil value (CFG-37)
      def override(key, value)
        @overrides[key!(key)] = Model.required!("value", value).to_s
        self
      end

      # CFG-10: drops only the override, so the lookup falls through to the other tiers as if the
      # key were never overridden; never installs a nil; a no-op for a key with no override.
      #
      # @return [self]
      def remove(key)
        @overrides.delete(key!(key))
        self
      end

      # Sets one entry of the third tier, the process-wide defaults §10.16 substitutes for a
      # system-property source. The key is stored VERBATIM: CFG-3's normalisation is a
      # lookup-side transform Configuration#string already performs, and CFG-4's raw accessor
      # reads this tier by the EXACT name -- its own text names https.proxyHost and
      # http.nonProxyHosts as the keys whose casing must survive. Folding here would make both
      # unreachable through the only in-SDK setter.
      #
      # @return [self]
      # @raise [Dexpace::InvalidArgumentError] on a nil or blank key or a nil value (CFG-37), or
      #   after an explicit #property_source=, whose seam this would silently shadow
      def property(key, value)
        if @property_source_explicit
          raise InvalidArgumentError, "property cannot be added after an explicit property_source="
        end

        @properties[key!(key)] = Model.required!("value", value).to_s
        self
      end

      # Replaces the property seam outright (CFG-11).
      #
      # @raise [Dexpace::InvalidArgumentError] on nil or a non-callable (CFG-37), or after
      #   #property, whose entries it would silently discard
      def property_source=(source)
        if @properties.any?
          raise InvalidArgumentError,
                "property_source= cannot follow property; the entries would be lost"
        end

        @property_source = source!("property_source", source)
        @property_source_explicit = true
      end

      # Replaces the environment seam (CFG-11).
      #
      # @raise [Dexpace::InvalidArgumentError] on nil or a non-callable (CFG-37)
      def env_source=(source)
        @env_source = source!("env_source", source)
      end

      # The frozen model; the builder stays usable and later mutation does not reach it (CFG-8).
      # An untouched inherited seam is passed through BY REFERENCE, never rebuilt: CFG-9 requires
      # `derived.property_source.equal?(receiver.property_source)`. When #property WAS called over
      # an inherited seam the two compose: the added entries shadow the inherited source, which is
      # CFG-13's last-write-wins at the key level.
      #
      # @return [Configuration]
      def build
        Configuration.build(overrides: @overrides, env_source: @env_source,
                            property_source: composed_source,)
      end

      # A property source this builder composed: its own entries shadowing one base source.
      # Frozen, and never nested -- composing over a Layered merges into a new one over the same
      # base (phase 10).
      class Layered
        attr_reader :entries, :base

        def initialize(entries, base)
          @entries = entries.to_h { |key, value| [key.to_s, value.to_s] }.freeze
          @base = base
          freeze
        end

        # This layer's own entry for the key, else the base source's answer (CFG-13's
        # last-write-wins at the key level).
        #
        # @param key [String]
        # @return [String, nil]
        def call(key) = @entries.fetch(key.to_s) { @base.call(key) }
      end
      private_constant :Layered

      private

      # Phase 10, repairing 5a's review R1-2: each `Dexpace.configure` that added a property over
      # an inherited source wrapped it in one more closure, so N configures built an N-deep chain
      # every property lookup walked, and none was ever released. A layer this builder made is now
      # FLATTENED -- its entries merged under the new ones, over the same base -- so the chain is
      # at most one layer over the base whatever the configure count. Last-write-wins per key
      # (CFG-13) and an untouched inherited seam passed through by reference (CFG-9) both hold.
      def composed_source
        inherited = @property_source #: untyped
        return inherited || Sources::NONE if @property_source_explicit || @properties.empty?

        added = Sources.from_hash(@properties)
        return added if inherited.nil? || Sources::NONE.equal?(inherited)
        if inherited.is_a?(Layered)
          return Layered.new(inherited.entries.merge(@properties),
                             inherited.base,)
        end

        Layered.new(@properties, inherited)
      end

      def key!(key)
        text = Model.required!("key", key).to_s.strip
        raise InvalidArgumentError, "key cannot be blank" if text.empty?

        text
      end

      def source!(name, source)
        Model.required!(name, source)
        unless source.respond_to?(:call)
          raise InvalidArgumentError, "#{name} must answer #call, got #{source.class}"
        end

        source
      end
    end
  end
end
