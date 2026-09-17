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

      # @param overrides [Hash] seed overrides, copied
      # @param env_source [#call] CFG-11's environment seam
      # @param property_source [#call, nil] an inherited property seam, or nil for none yet
      def initialize(overrides: {}, env_source: Sources::ENVIRONMENT, property_source: nil)
        @overrides = {} #: Hash[String, String]
        overrides.each { |key, value| @overrides[key.to_s] = value.to_s }
        @env_source = env_source
        @property_source = property_source
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

      private

      def composed_source
        inherited = @property_source
        return inherited || Sources::NONE if @property_source_explicit || @properties.empty?

        added = Sources.from_hash(@properties)
        return added unless inherited
        return added if Sources::NONE.equal?(inherited)

        ->(key) { added.call(key) || inherited.call(key) }.freeze
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
