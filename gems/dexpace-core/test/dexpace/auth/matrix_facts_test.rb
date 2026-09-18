# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "digest"
require "securerandom"
require "pp"
require "stringio"
require_relative "../../test_helper"
require_relative "../../../lib/dexpace/model"

# Exercises: AUTH-14, AUTH-17, AUTH-18, AUTH-20, AUTH-21 (the Ruby facts they rest on) -- the
# phase-6c plan's verified facts, re-run as a standing test on every CI row rather than once in
# a scratch script (5a's, 5b's and 5c's precedent), with the four Digest expectations DERIVED
# from their inputs here and compared with the values the handler suite commits. No lib/
# mirror: it asserts the interpreter, not a file.
class DexpaceAuthMatrixFactsTest < DexpaceTestCase
  test "AUTH-14: pack(\"m0\") base64-encodes the UTF-8 bytes into a US-ASCII String, no base64" do
    assert_equal("YWxpY2U6czNjcjN0", ["alice:s3cr3t"].pack("m0"))
    assert_equal(Encoding::US_ASCII, ["alice:s3cr3t"].pack("m0").encoding)
    assert_equal("w7w6cMOk", ["ü:pä"].pack("m0"))
  end

  test "String#unpack1(\"m\") is lenient: garbage decodes to whatever valid octets survive" do
    assert_equal("i\xB7".b, "!!a b c!!".unpack1("m"))
  end

  test "AUTH-17: MD5 and SHA-256 hexdigests are lower-case hex of 32 and 64 characters" do
    assert_match(/\A[0-9a-f]{32}\z/, Digest::MD5.hexdigest("x"))
    assert_match(/\A[0-9a-f]{64}\z/, Digest::SHA256.hexdigest("x"))
  end

  test "AUTH-18: format(\"%08x\", n & 0xFFFFFFFF) renders 8 lower-case hex digits and wraps" do
    assert_equal("00000001", format("%08x", 1))
    assert_equal("00000001", format("%08x", 0x100000001 & 0xFFFFFFFF))
    assert_equal("ffffffff", format("%08x", 0xFFFFFFFF))
  end

  test "AUTH-21: String#encode(ISO-8859-1) raises on an unmappable character, not a mappable one" do
    assert_raises(Encoding::UndefinedConversionError) { "日".encode(Encoding::ISO_8859_1) }
    assert_equal([112, 228], "pä".encode(Encoding::ISO_8859_1).bytes)
  end

  test "AUTH-20: SecureRandom.hex(16) is 32 lower-case hex characters, 128 bits" do
    100.times { assert_match(/\A[0-9a-f]{32}\z/, SecureRandom.hex(16)) }
  end

  test "AUTH-15's trap: a substring test accepts auth-int" do
    assert_includes("auth-int", "auth")
  end

  test "AUTH-8's trap: pp walks a Data's members and ignores an #inspect override" do
    klass = Data.define(:token) do
      def inspect = "#<redacted>"
    end
    output = StringIO.new
    PP.pp(klass.new(token: "SECRET"), output)

    assert_includes(output.string, "SECRET")
  end

  test "a Data's members are not ivars: the allocate-and-set trick leaves them nil" do
    klass = Data.define(:name)
    instance = klass.allocate
    instance.instance_variable_set(:@name, "X")

    assert_nil(instance.name)
  end

  test "AUTH-2's trap: dup.freeze is shallow, Model.own is deep" do
    scopes = [+"read"]
    shallow = scopes.dup.freeze
    deep = Dexpace::Model.own(scopes)
    scopes[0] << ":write"

    assert_equal(["read:write"], shallow)
    assert_equal(["read"], deep)
    assert_predicate(deep[0], :frozen?)
  end

  test "Thread::Mutex is not reentrant: the second synchronize raises ThreadError" do
    mutex = ::Thread::Mutex.new
    error = assert_raises(ThreadError) { mutex.synchronize { mutex.synchronize { :unreached } } }

    assert_includes(error.message, "recursive locking")
  end

  test "Gem::BUNDLED_GEMS::SINCE is undefined on the 3.2 floor and defined above it" do
    defined_here = defined?(Gem::BUNDLED_GEMS::SINCE) ? true : false

    assert_equal(RUBY_VERSION >= "3.3", defined_here)
  end

  # The four Digest expectations, derived from their inputs. RFC 2617 §3.5's published response
  # is a qop=auth value; RFC 7616 §3.9.1's printed SHA-256 response is 63 hex characters and is
  # not reproducible from its own inputs, so the two SHA-256 values are the ones this Ruby
  # produces from the RFC's inputs, and they are what digest_handler_test.rb commits.
  test "AUTH-17: the four Digest expectations derive from their inputs" do
    md5 = ->(text) { Digest::MD5.hexdigest(text) }
    ha1 = md5.call("Mufasa:testrealm@host.com:Circle Of Life")
    ha2 = md5.call("GET:/dir/index.html")
    nonce = "dcd98b7102dd2f0e8b11d0f600bfb0c093"

    assert_equal("6629fae49393a05397450978507c4ef1",
                 md5.call("#{ha1}:#{nonce}:00000001:0a4f113b:auth:#{ha2}"),)
    assert_equal("670fd8c2df070c60b045671b8b24ff02", md5.call("#{ha1}:#{nonce}:#{ha2}"))

    sha = ->(text) { Digest::SHA256.hexdigest(text) }
    s_nonce = "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v"
    s_cnonce = "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ"
    s_ha1 = sha.call("Jäsøn Doe:http-auth@example.org:Secret, or not?")
    s_ha2 = sha.call("GET:/doe.json")

    assert_equal("9fbf3e2223549127935ba79d47a0299af1f57eae1240ead830c0b47ad60346e1",
                 sha.call("#{s_ha1}:#{s_nonce}:00000001:#{s_cnonce}:auth:#{s_ha2}"),)
    session = sha.call("#{s_ha1}:#{s_nonce}:#{s_cnonce}")

    assert_equal("a0316f893cdcbd706441a5392ef9e690688b447acf4015a2b9ce520e6b551a5c",
                 sha.call("#{session}:#{s_nonce}:00000001:#{s_cnonce}:auth:#{s_ha2}"),)
  end
end
