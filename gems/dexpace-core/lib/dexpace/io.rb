# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "error/invalid_argument_error"

module Dexpace
  # The byte-streaming layer: one FIFO buffer, one buffered source/sink pair with typed reads and
  # non-consuming views, and one tee sink. Design §10.1 retired the provider seam that used to make
  # this pluggable, so the behavioural contract is the whole deliverable -- there is no registry,
  # no factory and no installation call here.
  #
  # HAZARD, stated where a reader meets it. This constant shadows ::IO for every file inside
  # `module Dexpace` AND inside a consumer's own `class C; include Dexpace`, because `include`
  # inserts Dexpace ahead of Object in C.ancestors. `x.is_a?(IO)` is then silently false for a
  # real ::IO, with no error and no warning, and a `case/when IO` falls through. A top-level
  # `include Dexpace` is unaffected, because Object's own constant table is searched first. Core
  # never writes `is_a?(IO)`: every stream this layer accepts is checked with respond_to?, and
  # Dexpace/QualifiedCoreConstant makes a bare `IO` inside `module Dexpace` a RuboCop offense.
  # No gate this repository owns reaches a consumer's file, which is why the same warning is owed
  # in docs/sdk-documentation/ before anything is published (docs/first-release.md).
  module IO
    # IO-9's ceiling, as the DEFAULT. Design §10.18 substitutes it for a host maximum single-array
    # allocation Ruby does not have, and §3.1 fixes the default at 64 MiB -- "chosen, not
    # derived". Nothing takes it as a keyword: every operation that produces one contiguous
    # String reads .max_materialized_bytes below, which is this constant unless the layered chain
    # says otherwise.
    MAX_MATERIALIZED_BYTES = 64 * 1024 * 1024

    # The effective ceiling: §3.1's "configurable through the same layered chain as every other
    # limit (§8.2)", the ceiling half of the body-logging caps phase 3b postponed to phase 5.
    # Read on EVERY call rather than memoised, so Dexpace.configure and Dexpace.reset_config! stay
    # effective -- the context-store-cap consequence, avoided where it is avoidable. A configured
    # value that is not a positive Integer falls back to the constant rather than making every
    # materialisation refuse. No `ceiling:` keyword is added anywhere, so phase 3's boundary
    # ("a ceiling: keyword on a preview operation would give one stream two ceilings") stands.
    #
    # @param configuration [Dexpace::Configuration] the chain to read; the process-wide slot by
    #   default
    # @return [Integer] the ceiling in bytes
    # @raise [Dexpace::InvalidArgumentError] when handed something that is not a Configuration
    def self.max_materialized_bytes(configuration = Dexpace.configuration)
      unless configuration.is_a?(Dexpace::Configuration)
        raise InvalidArgumentError,
              "configuration must be a Dexpace::Configuration, got #{configuration.class}"
      end

      value = configuration.integer(Configuration::Keys::MAX_MATERIALIZED_BYTES,
                                    default: MAX_MATERIALIZED_BYTES,)
      value.is_a?(::Integer) && value.positive? ? value : MAX_MATERIALIZED_BYTES
    end
  end
end
