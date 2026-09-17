# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"
require_relative "builder"
require_relative "error/invalid_argument_error"

module Dexpace
  # The immutable four-tier configuration chain (CFG-1 through CFG-13, CFG-37, CFG-38): a lookup
  # resolves an explicit override for the exact key, then the environment seam queried by the
  # exact key, then the property seam queried by the NORMALISED key, then the caller's default --
  # in that order even where it inverts Ruby convention, because CFG-1 is normative and a
  # conformance test written against it would observe the difference (design §10.16). The third
  # tier is §10.16's substituted source: the process-wide defaults Dexpace.configure installs,
  # not a second ENV read under another name.
  #
  # A frozen Data including Model, built only through .build, with the override map copied and
  # deep-frozen once at construction (CFG-8) and both seams held by reference (CFG-9, CFG-11).
  # No Ractor-shareability claim is made for it (P5-6): CFG-11 requires the seams to be
  # callables, and a frozen Data holding a lambda raises Ractor::IsolationError.
  #
  # This file declares the class and is the ONLY entry point to it: configuration/keys.rb,
  # configuration/sources.rb, configuration/parsers.rb and configuration/builder.rb are required
  # from inside its body, because the first two and the last reopen `class Configuration` with
  # no superclass clause and loading any of them before this declaration raises
  # `TypeError: superclass mismatch`.
  class Configuration < Data.define(:overrides, :env_source, :property_source)
    include Model

    private_class_method :new

    # The four argument checks the constructor and the accessors share. A private module rather
    # than private instance methods, because EMPTY is built at the foot of this class body and a
    # helper defined below it would not exist yet.
    module Guard
      extend self

      # A copy of the map with String keys and values, every value required (CFG-37).
      def stringify(map)
        copy = {} #: Hash[String, String]
        map.each_with_object(copy) do |(key, value), copy|
          Model.required!("override value for #{key.inspect}", value)
          copy[key.to_s] = value.to_s
        end
      end

      # A seam is anything answering #call (CFG-11), required (CFG-37).
      def source!(name, source)
        Model.required!(name, source)
        unless source.respond_to?(:call)
          raise InvalidArgumentError, "#{name} must answer #call, got #{source.class}"
        end

        source
      end

      # CFG-3's normalisation: downcased -- with no argument, Dexpace/NoLocaleCaseFold -- and
      # every underscore a dot, so MAX_RETRY_ATTEMPTS is queried as max.retry.attempts.
      def normalize(key)
        key.downcase.tr("_", ".")
      end

      # A lookup name is required (CFG-37) and read as a String.
      def key!(name)
        Model.required!("name", name)
        name.to_s
      end
    end
    private_constant :Guard

    # Validation lives here so #with, which routes through .build, meets it too.
    def initialize(overrides:, env_source:, property_source:)
      Model.required!("overrides", overrides)
      unless overrides.is_a?(::Hash)
        raise InvalidArgumentError, "overrides must be a Hash, got #{overrides.class}"
      end

      super(
        overrides: Model.own(Guard.stringify(overrides)),
        env_source: Guard.source!("env_source", env_source),
        property_source: Guard.source!("property_source", property_source),
      )
    end

    # @param overrides [Hash] the exact-name override map, copied and frozen (CFG-8)
    # @param env_source [#call] CFG-11's environment seam, from key to String?
    # @param property_source [#call] CFG-11's property seam, from exact key to String?
    # @return [Configuration]
    # @raise [Dexpace::InvalidArgumentError] on a nil argument (CFG-37), a non-Hash map, a nil
    #   value in it, or a seam that is not callable
    def self.build(overrides: {}, env_source: Sources::ENVIRONMENT, property_source: Sources::NONE)
      new(overrides: overrides, env_source: env_source, property_source: property_source)
    end

    # @return [Configuration::Builder] an empty builder over the platform-backed seams
    def self.builder
      Builder.new
    end

    # HTTP-3's builder split: a builder seeded from this configuration, with the override map
    # dup'ed -- never aliased -- and both seams passed by reference (CFG-9).
    #
    # @return [Configuration::Builder]
    def new_builder
      Builder.new(overrides: overrides.dup, env_source: env_source,
                  property_source: property_source,)
    end

    # The string lookup in CFG-1's strict order. Not #[] -- a Hash-like reader over the override
    # map is exactly the reading CFG-38 forbids.
    #
    # @param name [String, Symbol] the key, exact for the override and environment tiers
    # @param default [String, nil] the last tier, nullable (CFG-37's documented-nullable slot)
    # @return [String, nil]
    def string(name, default: nil)
      key = Guard.key!(name)
      return overrides[key] if overrides.key?(key)

      # CFG-2: a present-but-empty environment value is absent. The rule names the environment
      # layer and only that layer -- an empty override or property resolves to "".
      env_value = env_source.call(key)
      return env_value unless env_value.nil? || env_value.empty?

      property_value = property_source.call(Guard.normalize(key))
      property_value.nil? ? default : property_value
    end

    # CFG-4's raw read: the property tier alone, by the EXACT name, no normalisation -- how
    # https.proxyHost and http.nonProxyHosts keep their casing. Neither the override map nor the
    # environment is consulted, which is what keeps §10.16 one deviation applied twice.
    #
    # @param name [String, Symbol] the property name, verbatim
    # @param default [String, nil]
    # @return [String, nil]
    def raw_property(name, default: nil)
      value = property_source.call(Guard.key!(name))
      value.nil? ? default : value
    end

    # CFG-5 and CFG-38: the whole chain, then base-10 parsing; the default on absence or garbage.
    #
    # @return [Integer, nil]
    def integer(name, default: nil)
      ConfigParsers.parse_integer(string(name), default: default)
    end

    # CFG-6 and CFG-38: exactly "true" and "false", case-insensitively.
    #
    # @return [Boolean, nil]
    def boolean(name, default: nil)
      ConfigParsers.parse_boolean(string(name), default: default)
    end

    # CFG-7 and CFG-38: ISO-8601, `<number><unit>` or bare milliseconds, as Float SECONDS (P5-4).
    #
    # @return [Float, nil]
    def duration(name, default: nil)
      ConfigParsers.parse_duration(string(name), default: default)
    end

    # CFG-9's copy-on-write derivation: the override map is copied before the mutator runs and
    # the seams are inherited by reference unless the mutator replaces them; the receiver is
    # untouched. CFG-10's #remove is the builder's.
    #
    # @yieldparam builder [Configuration::Builder]
    # @return [Configuration] the derived configuration
    # @raise [Dexpace::InvalidArgumentError] without a block (CFG-37 names the derive mutator)
    def derive
      raise InvalidArgumentError, "derive block is required" unless block_given?

      builder = new_builder
      yield builder
      builder.build
    end

    # The four nested files reopen `class Configuration`, so they load HERE, inside the body the
    # declaration above created -- a nested file loaded first would make that declaration a
    # superclass mismatch, which is why none of the four appears in lib/dexpace.rb -- and EMPTY
    # follows them because it needs Sources::ENVIRONMENT at load time.
    require_relative "configuration/keys"
    require_relative "configuration/sources"
    require_relative "configuration/parsers"
    require_relative "configuration/builder"

    # CFG-13's "MUST default to an empty configuration (no overrides, platform-backed seams)".
    EMPTY = build(overrides: {}, env_source: Sources::ENVIRONMENT, property_source: Sources::NONE)
  end
end
