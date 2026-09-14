# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# HTTP-9, and the classification HTTP-7 consumes. The idempotent set is single-sourced here;
# phase 6's retry allow-list and replay-safety gate both derive from it and neither restates it.
class DexpaceMethodTest < DexpaceTestCase
  test "the canonical wire token is the uppercase name" do
    %w[GET HEAD POST PUT PATCH DELETE OPTIONS TRACE CONNECT].each do |token|
      assert_equal(token, Dexpace::Method.of(token.downcase).token)
      assert_equal(token, Dexpace::Method.of(token).to_s)
      assert_equal(Dexpace::Method.const_get(token), Dexpace::Method.of(token.downcase))
    end
  end

  test "classifies exactly GET HEAD OPTIONS PUT DELETE as idempotent" do
    idempotent = %w[GET HEAD OPTIONS PUT DELETE]

    assert_equal(idempotent, Dexpace::Method::IDEMPOTENT)
    idempotent.each { |token| assert_predicate(Dexpace::Method.of(token), :idempotent?) }
    %w[POST PATCH CONNECT TRACE].each do |token|
      refute_predicate(Dexpace::Method.of(token), :idempotent?)
    end
  end

  test "classifies exactly GET HEAD TRACE CONNECT as forbidding a body" do
    assert_equal(%w[GET HEAD TRACE CONNECT], Dexpace::Method::BODY_FORBIDDEN)
    %w[GET HEAD TRACE CONNECT].each do |token|
      assert_predicate(Dexpace::Method.of(token), :body_forbidden?)
    end
    %w[POST PUT PATCH DELETE OPTIONS].each do |token|
      refute_predicate(Dexpace::Method.of(token), :body_forbidden?)
    end
  end

  test "accepts an extension method that is a valid token" do
    assert_equal("PROPFIND", Dexpace::Method.of("propfind").token)
    refute_predicate(Dexpace::Method.of("propfind"), :idempotent?)
  end

  test "rejects a token carrying a separator or a control byte" do
    ["GET POST", "GET\r\n", "GE T", "", "GET/1", "G(T"].each do |token|
      assert_raises(Dexpace::InvalidArgumentError, token.inspect) { Dexpace::Method.of(token) }
    end
  end

  test "requires a token, naming the field, and refuses anything but a String or Symbol" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Method.of(nil) }

    assert_equal("token is required", error.message)
    assert_equal(Dexpace::Method::GET, Dexpace::Method.of(:get))
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Method.of(200) }
  end

  # The byte check runs before `upcase`, which would otherwise raise a raw ArgumentError from
  # inside Ruby and escape `rescue Dexpace::Error`.
  test "rejects a token carrying invalid UTF-8 with the SDK's own error" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Method.of("GE\xE9T") }

    refute_match(/invalid byte sequence/, error.message)
  end

  test "of is idempotent on a Method" do
    assert_same(Dexpace::Method::GET, Dexpace::Method.of(Dexpace::Method::GET))
  end

  test "with re-validates, so a derived method cannot carry a separator" do
    assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Method::GET.with(token: "GE T") }
    assert_equal(Dexpace::Method::POST, Dexpace::Method::GET.with(token: "post"))
  end

  # Visibility is asserted with respond_to?, never with assert_predicate. Minitest's
  # assert_predicate calls __send__, which sends straight past `private`: verified that a private
  # predicate passes assert_predicate on Minitest 5.25.1 (Ruby 3.2.11) and 6.0.0 (Ruby 4.0.6)
  # alike, and that refute_predicate catches it on 6.0.0 only. Task 14 calls
  # `method.body_forbidden?` with an explicit receiver, so a misplaced `private` here breaks a
  # later task, and on the declared floor no other assertion in this file would notice.
  test "the classification predicates are public, because a Request asks them by receiver" do
    %i[to_s idempotent? body_forbidden?].each do |name|
      assert_respond_to(Dexpace::Method::GET, name)
    end
    refute_respond_to(Dexpace::Method::GET, :token?)
  end

  test "the two classification sets are frozen" do
    assert_predicate(Dexpace::Method::IDEMPOTENT, :frozen?)
    assert_predicate(Dexpace::Method::BODY_FORBIDDEN, :frozen?)
  end
end
