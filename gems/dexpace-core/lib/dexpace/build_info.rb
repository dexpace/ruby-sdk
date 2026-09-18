# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "version"

module Dexpace
  # The static build and host-runtime descriptor (CFG-36): the SDK version and the runtime's
  # version, vendor and OS name, resolved once at load into frozen constants, each falling back to
  # the non-blank "unknown", and the ordered identity-token pair a User-Agent-style string is
  # composed from -- the SDK token first, the runtime token second.
  #
  # Every component is read off a constant that needs no `require` and is defined under
  # `--disable-gems` -- RUBY_ENGINE, RUBY_ENGINE_VERSION and RUBY_PLATFORM -- so the require
  # allowlist does not grow (R5). RbConfig would give the same OS token here and is undefined
  # without RubyGems; `rbconfig` is allowlistable at the cost of a reviewed one-line diff and
  # was not worth the first growth of that list since phase 0. RUBY_PLATFORM's OS half is not
  # always what an operator would call the operating system ("darwin24", "x86_64-linux-musl"),
  # and that is accepted: the token's destination is a User-Agent, where RUBY_PLATFORM is the
  # string the Ruby ecosystem already publishes. Composing the User-Agent itself is not this
  # module's job.
  module BuildInfo
    # The fallback CFG-36 fixes: never an empty token, so a joined identity string is never
    # malformed.
    UNKNOWN = "unknown"

    # The one blank guard, applied to every component so non-blankness is a property of the
    # constant rather than of its callers.
    def self.non_blank(value)
      text = value.to_s.strip
      text.empty? ? UNKNOWN : -text
    end
    private_class_method :non_blank

    # The SDK's own version, phase 0's Dexpace::VERSION from the repo-root VERSIONS file.
    SDK_VERSION = non_blank(Dexpace::VERSION)

    # The interpreter's version -- RUBY_ENGINE_VERSION, which is RUBY_VERSION on CRuby and the
    # engine's own on another implementation.
    RUNTIME_VERSION = non_blank(::RUBY_ENGINE_VERSION)

    # The interpreter's vendor: "ruby" on CRuby, "jruby", "truffleruby".
    RUNTIME_VENDOR = non_blank(::RUBY_ENGINE)

    # The OS half of RUBY_PLATFORM ("x86_64-linux" -> "linux").
    OS_NAME = non_blank(::RUBY_PLATFORM.split("-", 2).last)

    # CFG-36's "default ordered identity-token list (SDK token then runtime token)".
    # An interpolated literal is not frozen by the magic comment (Ruby >= 3.0), so each is.
    IDENTITY_TOKENS = [
      "dexpace-ruby/#{SDK_VERSION}".freeze,
      "#{RUNTIME_VENDOR}-#{RUNTIME_VERSION}/#{OS_NAME}".freeze,
    ].freeze
  end
end
