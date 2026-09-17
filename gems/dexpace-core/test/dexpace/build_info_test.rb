# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# CFG-36: the static build/runtime descriptor, resolved once at load, every token non-blank.
class DexpaceBuildInfoTest < DexpaceTestCase
  test "CFG-36: the four identity components are non-blank frozen Strings, resolved at load" do
    %i[SDK_VERSION RUNTIME_VERSION RUNTIME_VENDOR OS_NAME].each do |name|
      value = Dexpace::BuildInfo.const_get(name)

      assert_predicate(value, :frozen?, name.to_s)
      refute_empty(value.strip, name.to_s)
    end
    assert_equal("unknown", Dexpace::BuildInfo::UNKNOWN)
    assert_predicate(Dexpace::BuildInfo::UNKNOWN, :frozen?)
  end

  # R5: the three host-runtime components come from constants that need no require, so the
  # require allowlist does not grow and nothing here breaks under --disable-gems.
  test "CFG-36 / R5: the runtime identity is read off RUBY_ENGINE, its version and the platform" do
    assert_equal(Dexpace::VERSION, Dexpace::BuildInfo::SDK_VERSION)
    assert_equal(RUBY_ENGINE_VERSION, Dexpace::BuildInfo::RUNTIME_VERSION)
    assert_equal(RUBY_ENGINE, Dexpace::BuildInfo::RUNTIME_VENDOR)
    assert_equal(RUBY_PLATFORM.split("-", 2).last, Dexpace::BuildInfo::OS_NAME)
  end

  test "CFG-36: the identity-token list is the ordered pair SDK token, runtime token, frozen" do
    tokens = Dexpace::BuildInfo::IDENTITY_TOKENS

    assert_predicate(tokens, :frozen?)
    assert_equal(2, tokens.size)

    sdk_token, runtime_token = tokens

    assert_predicate(sdk_token, :frozen?)
    assert_predicate(runtime_token, :frozen?)
    assert_equal("dexpace-ruby/#{Dexpace::VERSION}", sdk_token)
    assert_equal("#{RUBY_ENGINE}-#{RUBY_ENGINE_VERSION}/#{RUBY_PLATFORM.split("-", 2).last}",
                 runtime_token,)
    # "Every token MUST be non-blank so joined identity strings are never malformed."
    tokens.each { |token| refute_match(/\s|\A\z/, token) }
    assert_equal("#{sdk_token} #{runtime_token}", tokens.join(" "))
  end

  # The blank guard is a property of the constant, not of its callers: fed a blank, it yields
  # "unknown" rather than an empty token.
  test "CFG-36: a blank component resolves to the non-blank 'unknown' rather than an empty token" do
    assert_equal("unknown", Dexpace::BuildInfo.send(:non_blank, ""))
    assert_equal("unknown", Dexpace::BuildInfo.send(:non_blank, "   "))
    assert_equal("unknown", Dexpace::BuildInfo.send(:non_blank, nil))
    assert_equal("x", Dexpace::BuildInfo.send(:non_blank, " x "))
    assert_predicate(Dexpace::BuildInfo.send(:non_blank, " x "), :frozen?)
  end
end
