# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../check"
require_relative "../runner"
require_relative "../vacuous"

module Dexpace
  module Conformance
    module PackagingSuite
      # Group 2, what a unit SHIPS: NFR-3, NFR-11 and NFR-13. A private_constant of
      # PackagingSuite.
      module Surface
        extend self

        # The async-framework namespaces NFR-11's first clause names ("coroutines, reactive
        # publishers"), as a Ruby ecosystem writes them. The negative lookbehind is what keeps
        # core's OWN `Dexpace::Async::Future` out of the match: the character before a leaked name
        # is never a colon.
        ASYNC_FRAMEWORKS = %w[Async Concurrent EventMachine Celluloid Reactor Fiber].freeze
        # A framework namespace at the START of a constant path. The lookbehind is what keeps
        # core's own `Dexpace::Async::Future` out of the match.
        LEAK = /(?<![:\w])(?:#{ASYNC_FRAMEWORKS.join("|")})::/
        # An RBS comment line, dropped before the scan so prose cannot fail a gem.
        COMMENT = /^\s*#/

        # NFR-3: "every exported declaration is deliberately marked public WITH A DECLARED TYPE."
        # The mechanised half, portable to any Ruby unit: every shipped implementation file has a
        # signature file beside it, one for one. A unit that ships a `lib/` file with no `sig/`
        # mirror has an exported declaration with no declared type, whatever its visibility.
        def explicit_typed_surface(subject)
          subject.every_name.each { |name| check_mirror(subject, name) }
          nil
        end

        def check_mirror(subject, name)
          lib, sig = trees(subject, name)
          raise Vacuous, "#{name} ships no lib/ tree, so there is nothing to mirror" if lib.nil?

          shipped = sig || [] #: Array[String]
          Check.that(lib == shipped,
                     "#{name} ships implementation files with no signature beside them, so part " \
                     "of its surface carries no declared type",
                     expected: lib - shipped, actual: shipped - lib, ids: ["NFR-3"],)
        end

        # NFR-11's first clause: "the core ... leaks no async-framework types (coroutines,
        # reactive publishers) into the core public surface."
        #
        # **A floor, and it says so.** The repository's own `gates:rbs_surface` resolves the
        # signature set with the `rbs` gem and refuses every constant outside `Dexpace::` and a
        # stdlib allowlist; this gem declares dexpace-core and nothing else, so it cannot parse
        # RBS and scans the shipped text instead, with `#` comment lines dropped. What it catches
        # is the clause the requirement actually names -- a framework namespace in a signature --
        # and what it does not catch is a foreign constant from some other library, which the
        # repository gate does. Stated rather than implied.
        def no_async_framework_type_in_the_core_surface(subject)
          leaks = leaks_in(subject.sig_root(subject.core_name))
          raise Vacuous, "#{subject.core_name} ships no sig/ tree to scan" if leaks.nil?

          Check.that(leaks.empty?,
                     "the core's public signatures name an async-framework type, so the core is " \
                     "not concurrency-model agnostic",
                     expected: [], actual: leaks.first(10), ids: ["NFR-11"],)
        end

        # NFR-13: "every source file SHOULD carry the project's license/SPDX header block."
        #
        # `sig/` ships inside every gem, so the signatures are shipped source -- and the header
        # gate is a RuboCop cop, which inspects Ruby and cannot parse `.rbs`. This assertion
        # asserts PRESENCE, so it goes GREEN the day the repair lands rather than red, which is
        # the direction a check should move under its own repair.
        def spdx_header_coverage(subject)
          roots = subject.every_name.filter_map { |name| subject.sig_root(name) }
            .select { |dir| ::File.directory?(dir) }
          raise Vacuous, "no unit ships a sig/ tree, so there is nothing to scan" if roots.empty?

          missing = subject.shipped_rbs_without_header

          Check.that(missing.empty?,
                     "shipped signature files carry no SPDX header; a RuboCop cop cannot reach " \
                     ".rbs, so nothing checks them",
                     expected: [], actual: missing.first(10), ids: ["NFR-13"],)
        end

        # @return [Array<String>, nil] every framework leak in a shipped sig/ tree, or nil when
        #   there is none to scan
        def leaks_in(root)
          return nil if root.nil? || !::File.directory?(root)

          ::Dir.glob(::File.join(root, "**", "*.rbs")).flat_map { |file| leaks_in_file(file) }
        end

        # @return [Array<String>] one `path:line: match` per leak in one signature file
        def leaks_in_file(file)
          ::File.readlines(file).filter_map.with_index do |line, index|
            next if line.match?(COMMENT)

            match = line[LEAK]
            "#{file}:#{index + 1}: #{match}" unless match.nil?
          end
        end

        # The two trees as relative, extension-free paths, so they compare directly.
        def trees(subject, name)
          root = subject.sig_root(name)
          return [nil, nil] if root.nil?

          gem_root = ::File.dirname(root)
          [relative(::File.join(gem_root, "lib"), ".rb"), relative(root, ".rbs")]
        end

        # @return [Array<String>, nil] every file under `root`, relative and extension-free
        def relative(root, extension)
          return nil unless ::File.directory?(root)

          ::Dir.glob("**/*#{extension}", base: root).map { |path| path.delete_suffix(extension) }
            .sort
        end

        ROWS = [
          ["NFR-3", "every shipped implementation file has a signature beside it",
           :explicit_typed_surface,],
          ["NFR-11", "the core's public signatures name no async-framework type",
           :no_async_framework_type_in_the_core_surface,],
          ["NFR-13", "every shipped signature file carries the SPDX header", :spdx_header_coverage],
        ].freeze
        private_constant :ROWS

        # @return [Array<Assertion>] this group's assertions, frozen
        ASSERTIONS = Runner.registry(self, ROWS)
      end
      private_constant :Surface
    end
  end
end
