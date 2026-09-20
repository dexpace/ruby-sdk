# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "json"
require "dexpace"

require_relative "json/version"

module Dexpace
  # Wire codecs: the serde seam's shipped implementations. The seam contract itself lives in
  # dexpace-core.
  module Serde
    # The reference wire codec, over Ruby's `json` gem: the seam's six methods on
    # Dexpace::Serde::JSON::Codec, the two factories here, the ISO-8601 encoder default and the
    # tri-state wiring inherited from core's Native walk, and the `json >= 2.19.9` floor -- declared
    # in this gem's gemspec, the only place it may be stated, and re-asserted below at require time.
    #
    # CAUTION: this module shadows ::JSON inside its own namespace. An unqualified `JSON.parse`
    # written anywhere under `Dexpace::Serde::JSON` resolves to this module, not to Ruby's, and
    # fails with a confusing NoMethodError. Every reference to Ruby's JSON from inside here is
    # written `::JSON`, and the Dexpace/QualifiedCoreConstant cop refuses the bare spelling.
    module JSON
      # The floor this gem declares in its gemspec and asserts at require time (P7-7). It is the
      # first json with JSON::Coder -- the per-instance, freezable, thread-safe engine SERDE-26's
      # private copy and SERDE-29's sharing rest on -- and the one carrying the 2026 advisories.
      # `bundler-audit` enforces the floor for a BUNDLED consumer in this repository's CI; it never
      # runs in a consumer's process, and an unbundled `require "dexpace/serde/json"` on a stock
      # Ruby 3.3 or 3.4 activates the interpreter's default json (2.7.2 / 2.9.1), which has no
      # Coder at all, while a stock 4.0 activates 2.18.0, which has one and is still below the
      # floor. Without this assertion the failure would be a NameError deep inside a codec, or no
      # failure and an unpatched parser.
      MINIMUM_JSON_VERSION = "2.19.9"

      # The core this adapter was built against, as design §2.4's registration-time version-skew
      # guard wants it: a two-segment pessimistic requirement, and never Dexpace::VERSION --
      # phase 2's Registry accepts only `~> M.N` and raises on "0.0.0", and the running core's own
      # version is a tautology. Public so a consumer debugging a skew failure can read the
      # constraint; equal to the gemspec's dexpace-core requirement, which the suite asserts.
      REQUIRED_CORE = "~> 0.0"

      class << self
        # SERDE-25's default-configuration factory: a FRESH, independently configured codec on
        # every call, never a shared instance, so an application that reconfigures the codec it
        # was handed cannot change the one another part of the process is using. This is also the
        # registry's factory (design §3.6).
        #
        # @return [Dexpace::Serde::JSON::Codec]
        def default = Codec.build

        # A codec over caller options. One positional Hash rather than a `**` splat, as
        # Dexpace::Model#with is spelled: Ruby passes keywords to a method declaring none as one
        # positional Hash, so `JSON.build(max_nesting: 4)` reads as it should while the empty call
        # allocates nothing (Dexpace/NoKeywordSplat) and an unknown key is the SDK's own
        # InvalidArgumentError rather than a keyword error whose shape differs between json 2.19.9
        # (which swallowed an unknown Coder option) and 3.0 (which refuses it).
        #
        # @param options [Hash{Symbol => Object}] see Codec.build
        # @return [Dexpace::Serde::JSON::Codec]
        # @raise [Dexpace::InvalidArgumentError] on an unknown option
        def build(options = nil) = Codec.build(options)
      end
    end
  end
end

# P7-7: the floor, asserted before the codec is even loaded, naming itself. A Gem::Version
# comparison needs no require. This runs at the TOP LEVEL, outside `module Dexpace`, so a bare
# `JSON` here is Ruby's (the shadowing hazard is lexical) and the cop set wants it unqualified.
if Gem::Version.new(JSON::VERSION) < Gem::Version.new(Dexpace::Serde::JSON::MINIMUM_JSON_VERSION)
  raise Dexpace::SeamError,
        "dexpace-serde-json requires json >= #{Dexpace::Serde::JSON::MINIMUM_JSON_VERSION}; " \
        "json #{JSON::VERSION} is active. Add `gem \"json\", \">= " \
        "#{Dexpace::Serde::JSON::MINIMUM_JSON_VERSION}\"` to the bundle, or activate it before " \
        "requiring this gem."
end

require_relative "json/codec"

# Design §3.6's require-time self-registration, with the version-skew guard on `core:` (design
# §2.4) -- spent here for the first time by an adapter with a third-party dependency. The factory
# is `.default`, so every resolution is a fresh codec (SERDE-25).
Dexpace::Serde.register(:json, -> { Dexpace::Serde::JSON.default },
                        core: Dexpace::Serde::JSON::REQUIRED_CORE,)
