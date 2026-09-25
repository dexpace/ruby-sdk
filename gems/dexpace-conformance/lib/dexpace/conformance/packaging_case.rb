# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "failure"
require_relative "vacuous"

module Dexpace
  module Conformance
    # What a PackagingSuite assertion receives. The subject is a set of gem NAMES resolved through
    # RubyGems, not paths: NFR-1's conformance clause names "the core artifact's PUBLISHED
    # dependency metadata", and only a resolved Gem::Specification is that (design P9-2). A source
    # gemspec and a published one can differ -- a gemspec that computes its dependencies, a build
    # that injects one, a `.gem` assembled from a different tree -- and phase 0's
    # `gates:gemspec_audit` is the pre-publication check over the source.
    #
    # **`resolve:` is what decides which of the two a run reads, and a run inside `bundle exec`
    # reads the SOURCE gemspec of a path gem.** Measured: `Gem::Specification.find_by_name` under
    # the repository's own bundle answers a spec whose `full_gem_path` is the source tree, and the
    # same call with the BUNDLE_* keys cleared raises `Gem::MissingSpecError`. So a run that means
    # P9-2's claim installs built `.gem` files and runs outside the bundle, and a run inside it
    # proves what `gates:gemspec_audit` already proves -- which is why every recorded result names
    # which environment produced it.
    #
    # No `require` is needed: RubyGems is loaded before user code, so Gem::Specification is
    # available without one -- which is what keeps this gem's declared dependency set at
    # dexpace-core and nothing else.
    class PackagingCase
      # Words a gem name spells lower-case that its constant path spells as an acronym, the two
      # this port's own gems use (NetHTTP, AsyncHTTP, Serde::JSON).
      ACRONYMS = %w[http json].freeze
      private_constant :ACRONYMS

      # Resolves a gem name to its installed specification, or nil when it is not installed.
      #
      # `Gem::LoadError` is named explicitly and is the WHOLE point of the rescue: RubyGems raises
      # `Gem::MissingSpecError` for a name it cannot resolve, and that descends from `Gem::LoadError
      # < LoadError < ScriptError`, so it is NOT a `StandardError` and a bare `rescue
      # ::StandardError` lets it past. It then escapes `Runner`'s own bare rescue too and aborts
      # the whole run, where the suite's contract is one :vacuous result naming the absent unit.
      # Measured 2026-09-23 on 4.0.6; the case is now driven in packaging_suite_test.rb.
      DEFAULT_RESOLVE = lambda do |name|
        ::Gem::Specification.find_by_name(name)
      rescue ::Gem::LoadError, ::StandardError
        nil
      end

      # @return [String] the core gem's name
      attr_reader :core_name
      # @return [Array<String>] the adapter gems' names
      attr_reader :adapter_names

      # @param core_name [String] the core gem's name
      # @param adapter_names [Array<String>] the adapters under audit
      # @param resolve [#call] name -> Gem::Specification or nil
      # @param constants [Hash{String => String}] gem name -> the constant path holding its VERSION
      # @param versions [Hash{String => String}] what the single source of truth states per gem
      # @param sig_roots [Hash{String => String}] gem name -> a shipped sig/ root, when the
      #   resolved spec's own path is not where the signatures are (a test seam, and the only way
      #   NFR-13's assertion can be driven against a hand-built specification)
      def initialize(core_name:, adapter_names:, resolve: DEFAULT_RESOLVE, constants: {},
                     versions: {}, sig_roots: {})
        @core_name = core_name
        @adapter_names = adapter_names
        @resolve = resolve
        @constants = constants
        @versions = versions
        @sig_roots = sig_roots
      end

      # @return [Hash{String => String}] what the driver's single source of truth states, keyed by
      #   gem name; empty when the driver named none
      attr_reader :versions

      # @param name [String] a gem name
      # @return [Gem::Specification]
      # @raise [Vacuous] when the gem is not installed, which is an absent antecedent and not a
      #   failure -- a porter running this suite against one gem has the others absent by design
      def spec(name)
        found = @resolve.call(name)
        if found.nil?
          raise Vacuous,
                "#{name} is not installed, so its published metadata cannot be read"
        end

        found
      end

      # @return [Array<String>] the core gem and every adapter, in order
      def every_name
        [@core_name, *@adapter_names]
      end

      # NFR-15's runtime half. `constants:` maps each gem name to its constant path and is what a
      # real run passes: the derived default below is a convenience for a porter and is WRONG for
      # this repository's own gems -- dexpace-core is `Dexpace`, not `Dexpace::Core`, and
      # `net_http` -> `NetHTTP` is not a mechanical casing.
      #
      # An unloaded path is :vacuous (nothing to read). A LOADED module with no VERSION is
      # :failed: the gem is present and reports no version at runtime, which is the defect NFR-15
      # names, not an absent antecedent.
      #
      # @param name [String] a gem name
      # @return [String] the version the loaded constant reports
      def runtime_version(name)
        path = @constants.fetch(name) { default_constant_path(name) }
        scope = resolve_constant(path)
        unless scope.const_defined?(:VERSION, false)
          raise Failure.new("#{path} is loaded but defines no VERSION",
                            expected: "#{path}::VERSION", actual: "undefined",
                            requirement_ids: ["NFR-15"],)
        end

        scope.const_get(:VERSION, false).to_s
      end

      # The shipped `.rbs` files with no SPDX header. NFR-13's conformance clause is "scan ALL
      # source files", and `sig/` ships inside every gem, so this is the half no RuboCop cop can
      # reach -- `.rbs` is not Ruby and no cop parses it.
      #
      # @return [Array<String>] every shipped signature file missing the header
      def shipped_rbs_without_header
        every_name.flat_map { |name| unheadered(sig_root(name)) }
      end

      # @param name [String] a gem name
      # @return [String, nil] where that gem's shipped signatures are, or nil when it has none
      def sig_root(name)
        return @sig_roots[name] if @sig_roots.key?(name)

        root = @resolve.call(name)&.full_gem_path
        root.nil? ? nil : ::File.join(root, "sig")
      end

      private

      def unheadered(root)
        return [] if root.nil? || !::File.directory?(root)

        ::Dir.glob(::File.join(root, "**", "*.rbs")).reject do |file|
          ::File.foreach(file).first(2).any? { |line| line.include?("SPDX-License-Identifier") }
        end
      end

      def resolve_constant(path)
        path.split("::").reduce(::Object) do |mod, segment|
          unless mod.const_defined?(segment, false)
            raise Vacuous, "#{path} is not loaded, so no runtime version can be read"
          end

          mod.const_get(segment, false)
        end
      end

      # The gem-name -> constant-path rule, segment for segment, with the two exceptions this
      # port's own six gems need (phase 10, phase 9's aggregate-run finding): a `-core` gem is its
      # root namespace (`dexpace-core` -> `Dexpace`), and a word in ACRONYMS is upper-cased
      # (`net_http` -> `NetHTTP`, `json` -> `JSON`). Before it, four of the six needed the
      # `constants:` override; a gem this rule still misses keeps that override.
      def default_constant_path(name)
        segments = name.split("-")
        segments = segments.first(1) if segments.size == 2 && segments.last == "core"
        segments.map { |segment| segment.split("_").map { |word| constant_word(word) }.join }
          .join("::")
      end

      def constant_word(word) = ACRONYMS.include?(word) ? word.upcase : word.capitalize
    end
  end
end
