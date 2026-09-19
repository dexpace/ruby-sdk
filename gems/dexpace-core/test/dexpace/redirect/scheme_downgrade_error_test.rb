# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"
require_relative "../../test_helper"
require "dexpace"

# Exercises: REDIR-15, XCUT-19 -- the clear error an HTTPS -> HTTP hop raises by default: a
# Dexpace::Error naming the two authorities and the opt-in, and never a path or a query. The
# raise site, the close before it and the emission beside it are asserted in step_test.rb.
class DexpaceRedirectSchemeDowngradeErrorTest < DexpaceTestCase
  PARSER = ::URI::RFC3986_PARSER

  def error(from, to)
    Dexpace::Redirect::SchemeDowngradeError.new(from: PARSER.parse(from), to: PARSER.parse(to))
  end

  test "REDIR-15: the message names both authorities, the downgrade and the opt-in" do
    message = error("https://a.example/x", "http://b.example/y").message

    assert_includes(message, "https://a.example")
    assert_includes(message, "http://b.example")
    assert_includes(message, "HTTPS to HTTP")
    assert_includes(message, "allow_scheme_downgrade: true")
  end

  test "REDIR-15: a non-default port is named; a default one is not" do
    message = error("https://a.example:8443/x", "http://b.example:80/y").message

    assert_includes(message, "https://a.example:8443")
    assert_includes(message, "http://b.example ")
    refute_includes(message, ":80")
  end

  test "XCUT-19: neither the path nor the query reaches the message" do
    message = error("https://a.example/v1/private?sig=SECRET", "http://b.example/z?token=T").message

    refute_includes(message, "SECRET")
    refute_includes(message, "token=T")
    refute_includes(message, "/v1/private")
  end

  test "is caught by rescue Dexpace::Error through Module#===" do
    caught = begin
      raise error("https://a.example/", "http://a.example/")
    rescue Dexpace::Error => error
      error
    end

    assert_instance_of(Dexpace::Redirect::SchemeDowngradeError, caught)
    assert_kind_of(Dexpace::Suppressible, caught)
    assert_operator(Dexpace::Redirect::SchemeDowngradeError, :<, ::StandardError)
  end
end
