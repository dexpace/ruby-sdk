# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

require_relative "thread/version"

module Dexpace
  # Async-runtime adapters: the async seam's shipped implementations. The seam contract itself
  # lives in dexpace-core.
  module Async
    # The zero-third-party async driver (phase 8b): a bounded worker pool over ::Thread and
    # ::Thread::SizedQueue that satisfies SEAM-18's caller-supplied-executor contract and settles
    # the core-owned pivot (design §2.1's charter sentence). See Dexpace::Async::Thread::Pool for
    # the whole surface; this module carries VERSION, REQUIRED_CORE and the version-skew guard and
    # nothing else -- there is no module-level default pool and no `.post` here
    # (concurrency-and-async/a1ec6ce4; SEAM-18): construct `Pool.build(size:)` explicitly, in the
    # caller's own code, where the size decision belongs.
    #
    # CAUTION: this module shadows ::Thread inside its own namespace. An unqualified
    # `Thread.new` written anywhere under `Dexpace::Async::Thread` resolves to this module, not
    # to Ruby's, and fails with a confusing NoMethodError -- and `x.is_a?(Thread)` is silently
    # false for a real thread. Every reference to Ruby's Thread from inside here is written
    # `::Thread`, and the Dexpace/QualifiedCoreConstant cop refuses the bare spelling.
    module Thread
      # The `~> MAJOR.MINOR` requirement this gem was built against, identical to the string the
      # gemspec's `add_dependency "dexpace-core", ...` line declares -- 7a's spelling, on its
      # precedent. `gates:gemspec_audit` checks the agreement from the gemspec side; the gem's
      # own suite checks it from this side.
      REQUIRED_CORE = "~> 0.0"

      # Design §2.4's registration-time version-skew guard, made directly (P8-21): SEAM-18
      # requires the executor to be caller-supplied with no default, so there is no executor
      # registry to register into (P2-1) and Registry#register's `core:` keyword -- the guard's
      # usual vehicle -- has no seam to travel through. The assertion is the boundary's substance
      # and is kept; it runs BEFORE the require_relative chain below, so a skewed pair fails at
      # `require` rather than at the first #post.
      #
      # Gem::Version and Gem::Requirement are used directly with no `require`: they are constants
      # RubyGems defines before any gem's own code runs, and this gem is only ever loaded as an
      # installed or bundled gem. dexpace-core hand-rolls the same comparison because it must
      # also work under `ruby --disable-gems`, a constraint that binds core and no adapter.
      #
      # @param core_version [String] the loaded dexpace-core's VERSION
      # @return [nil]
      # @raise [Dexpace::SeamError] naming both versions when the loaded core does not satisfy
      #   REQUIRED_CORE
      def self.assert_core_version!(core_version)
        wanted = ::Gem::Requirement.new(REQUIRED_CORE)
        return nil if wanted.satisfied_by?(::Gem::Version.new(core_version))

        raise Dexpace::SeamError,
              "dexpace-async-thread #{VERSION} was built against dexpace-core #{REQUIRED_CORE}, " \
              "but dexpace-core #{core_version} is loaded"
      end
      private_class_method :assert_core_version!

      assert_core_version!(Dexpace::VERSION)
    end
  end
end

require_relative "thread/rejected_error"
require_relative "thread/pool"
