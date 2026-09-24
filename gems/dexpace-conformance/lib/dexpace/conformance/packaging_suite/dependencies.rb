# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../failure"
require_relative "../runner"
require_relative "../vacuous"

module Dexpace
  module Conformance
    module PackagingSuite
      # Group 1, what a unit DECLARES: NFR-1, NFR-2, NFR-10, NFR-14 and NFR-15.
      # A private_constant of PackagingSuite.
      module Dependencies
        extend self

        # NFR-1: "the core module MUST depend only on the language standard library ... it MUST
        # NOT carry a runtime dependency on any concrete HTTP transport, serialization library,
        # I/O implementation, or async framework."
        #
        # EMPTY, not "contains no transport": Ruby has no compile-versus-runtime dependency scope
        # to lean on, so any non-empty set is a claim someone has to adjudicate.
        def core_has_no_runtime_dependencies(subject)
          names = subject.spec(subject.core_name).runtime_dependencies.map(&:name)

          Check.that(names.empty?, "#{subject.core_name} declares runtime dependencies",
                     expected: [], actual: names, ids: ["NFR-1"],)
        end

        # NFR-2: "a separately installable unit that depends on the core plus AT MOST ONE
        # third-party library." Both halves: the core is declared, and the rest is at most one.
        def adapter_budget(subject)
          subject.adapter_names.each do |name|
            declared = subject.spec(name).runtime_dependencies.map(&:name)
            third_party = declared - [subject.core_name]
            next if declared.include?(subject.core_name) && third_party.size <= 1

            raise Failure.new("#{name} is outside NFR-2's dependency budget",
                              expected: "#{subject.core_name} plus at most one",
                              actual: declared, requirement_ids: ["NFR-2"],)
          end
          nil
        end

        # NFR-10: "the SDK MUST declare a lowest-supported-runtime floor and target it for all
        # general-purpose units. A capability that genuinely requires a newer runtime MUST be
        # ISOLATED into its own unit that declares the higher floor explicitly; that unit MUST NOT
        # be a hard dependency of the general-purpose core."
        #
        # A HIGHER floor on one unit is therefore CONFORMING and not a defect -- which is the half
        # a gate asserting "every gemspec equals the global floor" gets wrong, and the reason this
        # assertion exists beside that gate rather than restating it.
        def declared_runtime_floor(subject)
          floors = subject.every_name.to_h do |name|
            [name, subject.spec(name).required_ruby_version]
          end
          undeclared = floors.reject { |_, floor| declared?(floor) }.keys
          Check.that(undeclared.empty?, "a unit declares no lowest-supported-runtime floor",
                     expected: "every unit declares one", actual: undeclared, ids: ["NFR-10"],)
          check_isolation(subject, floors)
        end

        # A unit whose floor is higher than the core's must not be a hard dependency of the core.
        def check_isolation(subject, floors)
          core_floor = floors.fetch(subject.core_name)
          raised = floors.reject { |name, floor| name == subject.core_name || floor == core_floor }
          declared = subject.spec(subject.core_name).runtime_dependencies.map(&:name)

          Check.that(!raised.keys.intersect?(declared),
                     "a unit declaring a HIGHER runtime floor is a hard dependency of the core, " \
                     "so the core no longer targets the floor it declares",
                     expected: [], actual: raised.keys & declared, ids: ["NFR-10"],)
        end

        # NFR-14: "dependency versions, plugin/tool versions and project coordinates SHOULD live
        # in a SINGLE SOURCE OF TRUTH rather than being restated per unit."
        #
        # The source is the driver's to name -- a porter's is not this repository's `VERSIONS`
        # file -- so the assertion is that every unit's PUBLISHED version equals the one that
        # source states for it. With no source supplied it is :vacuous with that reason, never a
        # pass, because "nobody told us" is not evidence of a single source. A source naming SOME
        # units states nothing about the rest, so those are skipped rather than failed -- the
        # declaration is the driver's, and this assertion checks it rather than inventing one.
        def single_version_source(subject)
          stated = subject.versions
          raise Vacuous, "no single source of truth was named for any unit" if stated.empty?

          mismatched = subject.every_name.filter_map do |name|
            published = subject.spec(name).version.to_s
            want = stated[name]
            next if want.nil? || want.to_s == published

            [name, want.to_s, published]
          end

          Check.that(mismatched.empty?,
                     "a unit's published version does not equal the single source's entry for it",
                     expected: "every unit at its declared version", actual: mismatched,
                     ids: ["NFR-14"],)
        end

        # NFR-15: "published artifacts SHOULD embed self-identifying version metadata that the SDK
        # can resolve AT RUNTIME, so runtime-emitted identifiers report the REAL version rather
        # than an 'unknown' placeholder fallback."
        #
        # So the assertion COMPARES the loaded constant against the resolved gemspec's version. A
        # not-a-placeholder check alone passes at 0.0.0 -- the version every gem in this
        # repository currently carries -- which would make it green on a tree where NFR-15 has
        # never been satisfied.
        def version_matches_the_gemspec(subject)
          subject.every_name.each do |name|
            built = subject.spec(name).version.to_s
            reported = subject.runtime_version(name)
            next if reported == built

            raise Failure.new("#{name}'s runtime version does not equal its build version",
                              expected: built, actual: reported, requirement_ids: ["NFR-15"],)
          end
          nil
        end

        # A `Gem::Requirement` of `>= 0` is RubyGems' default and declares nothing.
        def declared?(floor)
          !floor.nil? && floor.to_s != ">= 0"
        end

        ROWS = [
          ["NFR-1", "core declares zero runtime dependencies", :core_has_no_runtime_dependencies],
          ["NFR-2", "each adapter declares the core plus at most one library", :adapter_budget],
          ["NFR-10", "every unit declares a runtime floor, and a higher one stays isolated",
           :declared_runtime_floor,],
          ["NFR-14", "every unit's version comes from one source of truth", :single_version_source],
          ["NFR-15", "each unit reports its build version at runtime",
           :version_matches_the_gemspec,],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Dependencies
    end
  end
end
