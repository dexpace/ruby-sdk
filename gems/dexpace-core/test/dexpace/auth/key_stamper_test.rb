# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/key_stamper"
require_relative "../../../lib/dexpace/auth/key_credential"
require_relative "../../../lib/dexpace/auth/named_key_credential"
require_relative "../../support/auth_fixtures"

# Exercises: AUTH-26 -- the key written into the configured header, Authorization by default,
# a configured prefix prepended with exactly one space, and a stamper stateless after
# construction; the header SET rather than added, and the value checked against the outbound
# grammar once.
class DexpaceAuthKeyStamperTest < DexpaceTestCase
  include AuthFixtures

  KeyStamper = Dexpace::Auth::KeyStamper
  KeyCredential = Dexpace::Auth::KeyCredential
  NamedKeyCredential = Dexpace::Auth::NamedKeyCredential

  test "AUTH-26: the key goes into the configured header, defaulting to Authorization" do
    stamped = KeyStamper.new(KeyCredential.new(api_key: "abc")).call(https_request)

    assert_equal(["abc"], stamped.headers["Authorization"])
    stamped = KeyStamper.new(KeyCredential.new(api_key: "abc",
                                               header_name: "X-Api-Key",)).call(https_request)

    assert_equal(["abc"], stamped.headers["X-Api-Key"])
    assert_nil(stamped.headers["Authorization"])
  end

  test "AUTH-26: a configured prefix is prepended with a single space, for both key types" do
    named = NamedKeyCredential.new(name: "n", key: "abc", prefix: "SharedAccessKey")
    keyed = KeyCredential.new(api_key: "abc", prefix: "Key")

    assert_equal(["SharedAccessKey abc"],
                 KeyStamper.new(named).call(https_request).headers["Authorization"],)
    assert_equal(["Key abc"], KeyStamper.new(keyed).call(https_request).headers["Authorization"])
  end

  test "AUTH-26: stateless after construction -- the same value every call, frozen, no ivar set" do
    stamper = KeyStamper.new(KeyCredential.new(api_key: "abc"))
    before = stamper.instance_variables.map { |name| stamper.instance_variable_get(name) }
    first = stamper.call(https_request)
    second = stamper.call(https_request)

    assert_equal(first.headers["Authorization"], second.headers["Authorization"])
    assert_predicate(stamper, :frozen?)
    assert_equal(before, stamper.instance_variables.map do |name|
      stamper.instance_variable_get(name)
    end,)
  end

  test "the header is SET: re-stamping a stamped request replaces rather than appends" do
    stamper = KeyStamper.new(KeyCredential.new(api_key: "abc"))
    twice = stamper.call(stamper.call(https_request))

    assert_equal(["abc"], twice.headers["Authorization"])
  end

  test "the request is not mutated: a new request carries the header, the original does not" do
    original = https_request
    stamped = KeyStamper.new(KeyCredential.new(api_key: "abc")).call(original)

    assert_nil(original.headers["Authorization"])
    refute_same(original, stamped)
  end

  test "a credential without the three readers, or a value the wire refuses, fails to construct" do
    assert_raises(Dexpace::InvalidArgumentError) { KeyStamper.new(Object.new) }
    ["clé", "a\r\nb"].each do |unsendable|
      assert_raises(Dexpace::InvalidArgumentError) do
        KeyStamper.new(KeyCredential.new(api_key: unsendable))
      end
    end
  end
end
