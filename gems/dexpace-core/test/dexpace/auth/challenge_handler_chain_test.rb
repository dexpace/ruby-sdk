# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/challenge_handler_chain"
require_relative "../../../lib/dexpace/auth/basic_handler"
require_relative "../../../lib/dexpace/auth/digest_handler"
require_relative "../../../lib/dexpace/auth/step"
require_relative "../../support/auth_fixtures"

# Exercises: AUTH-23, AUTH-25, AUTH-30 -- the composing handler: first handler in declaration
# order, a defensive copy of the list, nil when nothing satisfies, the header NAME from the
# explicit proxy flag, and the hook adapter that is the only place a handler's VALUE becomes a
# header on a request.
class DexpaceAuthChallengeHandlerChainTest < DexpaceTestCase
  include AuthFixtures

  Chain = Dexpace::Auth::ChallengeHandlerChain

  def credential = Dexpace::Auth::PasswordCredential.build(username: "a", password: "b")
  def basic = Dexpace::Auth::BasicHandler.new(credential)
  def digest = Dexpace::Auth::DigestHandler.new(credential)

  BOTH = 'Digest realm="r", nonce="n", Basic realm="r"'

  test "AUTH-23: delegates to the first handler in declaration order whose check passes" do
    assert_match(/\ADigest /, Chain.new([digest, basic]).authorization_for(BOTH, https_request))
    assert_match(/\ABasic /, Chain.new([basic, digest]).authorization_for(BOTH, https_request))
    assert_match(/\ABasic /,
                 Chain.new([digest, basic]).authorization_for('Basic realm="r"', https_request),)
  end

  test "AUTH-23: a defensive copy at construction -- later caller mutation cannot reorder it" do
    handlers = [basic]
    chain = Chain.new(handlers)
    handlers.clear
    handlers << digest

    refute_nil(chain.authorization_for('Basic realm="r"', https_request))
    assert_predicate(chain, :frozen?)
  end

  test "AUTH-25: nil when no handler can satisfy any offered challenge -- never an empty header" do
    assert_nil(Chain.new([]).authorization_for(BOTH, https_request))
    assert_nil(Chain.new([basic]).authorization_for('Digest realm="r", nonce="n"', https_request))
    assert_nil(Chain.new([digest]).authorization_for('Digest realm="r", qop="auth-int", nonce="n"',
                                                     https_request,))
    assert_nil(Chain.new([basic, digest]).authorization_for("NTLM", https_request))
    assert_nil(Chain.new([basic]).authorization_for(nil, https_request))
  end

  test "AUTH-25: the header name comes from the explicit proxy flag alone" do
    chain = Chain.new([])

    assert_equal("Authorization", chain.header_name(proxy: false))
    assert_equal("Proxy-Authorization", chain.header_name(proxy: true))
  end

  test "AUTH-25, AUTH-30: the hook yields a replacement carrying the selected header, SET" do
    already = https_request(headers: Dexpace::Headers.builder.add("Authorization", "old").build)
    replacement = Chain.new([basic]).as_challenge_hook.call('Basic realm="r"', already,
                                                            unauthorized,)

    assert_equal(["Basic YTpi"], replacement.headers["Authorization"])
    assert_nil(replacement.headers["Proxy-Authorization"])
    assert_equal(already.url, replacement.url)
  end

  test "AUTH-25: with the proxy flag the hook writes Proxy-Authorization and not Authorization" do
    replacement = Chain.new([basic]).as_challenge_hook(proxy: true)
      .call('Basic realm="r"', https_request, unauthorized)

    assert_equal(["Basic YTpi"], replacement.headers["Proxy-Authorization"])
    assert_nil(replacement.headers["Authorization"])
  end

  test "AUTH-25: the hook yields nil, not an empty header, when no handler satisfies" do
    assert_nil(Chain.new([]).as_challenge_hook.call('Digest realm="r", nonce="n"', https_request,
                                                    unauthorized,))
  end

  test "AUTH-30: the chain is never the default hook -- the default yields no replacement" do
    assert_nil(Dexpace::Auth::Step::NO_REPLACEMENT.call('Basic realm="r"', https_request,
                                                        unauthorized,))
  end

  test "the hook is a three-argument callable the step accepts" do
    assert(Dexpace::Registry.callable?(Chain.new([basic]).as_challenge_hook, arity: 3))
    Dexpace::Auth::Step.build(stamper: Dexpace::Auth::Step::NO_STAMP,
                              challenge_hook: Chain.new([digest]).as_challenge_hook,)
  end

  test "the handlers must be an Array of objects answering #authorization_for" do
    assert_raises(Dexpace::InvalidArgumentError) { Chain.new(basic) }
    assert_raises(Dexpace::InvalidArgumentError) { Chain.new([Object.new]) }
    assert_raises(Dexpace::InvalidArgumentError) { Chain.new(nil) }
  end
end
