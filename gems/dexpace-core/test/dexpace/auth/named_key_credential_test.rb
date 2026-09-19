# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "pp"
require "stringio"
require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/named_key_credential"

# Exercises: AUTH-8, AUTH-9, AUTH-26 -- the named-key credential: non-blank name AND key,
# reference identity, the key redacted and the name (AUTH-8's non-secret "key name") visible.
class DexpaceAuthNamedKeyCredentialTest < DexpaceTestCase
  NamedKeyCredential = Dexpace::Auth::NamedKeyCredential

  test "AUTH-9: both the name and the key must be non-blank" do
    assert_raises(Dexpace::InvalidArgumentError) { NamedKeyCredential.new(name: "", key: "k") }
    assert_raises(Dexpace::InvalidArgumentError) { NamedKeyCredential.new(name: " ", key: "k") }
    assert_raises(Dexpace::InvalidArgumentError) { NamedKeyCredential.new(name: "n", key: "") }
    assert_raises(Dexpace::InvalidArgumentError) { NamedKeyCredential.new(name: "n", key: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { NamedKeyCredential.new(name: nil, key: "k") }
  end

  test "AUTH-26: the readers the stamper is written against" do
    credential = NamedKeyCredential.new(name: "n", key: "k", prefix: "SharedAccessKey")

    assert_equal("n", credential.name)
    assert_equal("k", credential.key_value)
    assert_equal("Authorization", credential.header_name)
    assert_equal("SharedAccessKey", credential.prefix)
  end

  test "AUTH-8: reference identity" do
    a = NamedKeyCredential.new(name: "n", key: "k")

    refute_equal(a, NamedKeyCredential.new(name: "n", key: "k"))
    assert_equal([a], [a] & [a])
  end

  test "AUTH-8: the key is redacted in every rendering; the name stays visible" do
    credential = NamedKeyCredential.new(name: "key-name", key: "super-secret-key")
    output = StringIO.new
    PP.pp(credential, output)

    [credential.to_s, credential.inspect, output.string].each do |text|
      refute_includes(text, "super-secret")
      assert_includes(text, "key-name")
    end
  end

  test "frozen at the end of construction" do
    assert_predicate(NamedKeyCredential.new(name: "n", key: "k"), :frozen?)
  end
end
