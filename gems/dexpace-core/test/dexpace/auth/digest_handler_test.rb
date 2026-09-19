# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/digest_handler"
require_relative "../../support/auth_fixtures"
require_relative "../../support/challenge_fixtures"
require_relative "../../support/fixed_cnonce"

# Exercises: AUTH-15 through AUTH-24 -- RFC 7616 Digest against RFC 2617 §3.5's genuine
# qop=auth vector and three DERIVED expectations (the legacy no-qop form of the same inputs,
# and RFC 7616 §3.9.1's inputs under SHA-256 and SHA-256-sess: the RFC's printed response is 63
# hex characters and no SHA-256 digest is, so only values matrix_facts_test.rb produced are
# committed), the selection rules, the counter, the encodings, the quoting and the wire forms
# the port decided. Split into nested cases under Metrics/ClassLength.
class DexpaceAuthDigestHandlerTest < DexpaceTestCase
  DigestHandler = Dexpace::Auth::DigestHandler
  Challenge = Dexpace::Auth::Challenge
  Challenges = Dexpace::Auth::Challenges
  PasswordCredential = Dexpace::Auth::PasswordCredential
  LIB = File.expand_path("../../../lib/dexpace/auth/digest_handler.rb", __dir__)

  # Shared across the nested cases.
  module Fixtures
    include AuthFixtures

    RFC2617_NONCE = "dcd98b7102dd2f0e8b11d0f600bfb0c093"
    RFC7616_NONCE = "7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v"
    RFC7616_CNONCE = "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ"
    # Derived on 3.2.11, 3.3.12, 3.4.10 and 4.0.6 (Task 1), identical on every row.
    MD5_QOP_AUTH = "6629fae49393a05397450978507c4ef1"
    MD5_LEGACY = "670fd8c2df070c60b045671b8b24ff02"
    SHA256 = "9fbf3e2223549127935ba79d47a0299af1f57eae1240ead830c0b47ad60346e1"
    SHA256_SESS = "a0316f893cdcbd706441a5392ef9e690688b447acf4015a2b9ce520e6b551a5c"

    def credential(username: "u", password: "p")
      PasswordCredential.build(username: username, password: password)
    end

    def mufasa = credential(username: "Mufasa", password: "Circle Of Life")

    def jason = credential(username: "Jäsøn Doe", password: "Secret, or not?")

    def handler(cred = credential, **) = DigestHandler.new(cred, **)

    def fixed(value) = FixedCnonce.new(value)

    def digest(**params)
      defaults = { "realm" => "r", "nonce" => "n" }
      Challenge.build(scheme: "digest",
                      params: defaults.merge(params.transform_keys(&:to_s)).compact,)
    end

    def mufasa_challenge(qop:, algorithm: nil)
      digest(realm: "testrealm@host.com", nonce: RFC2617_NONCE, algorithm: algorithm,
             opaque: "5ccc069c403ebaf9f0171e9517f40e41", qop: qop,)
    end

    def jason_challenge(algorithm)
      digest(realm: "http-auth@example.org", qop: "auth", algorithm: algorithm,
             nonce: RFC7616_NONCE, opaque: "FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS",
             charset: "UTF-8",)
    end

    def request(path = "/dir/index.html", method: "GET")
      Dexpace::Request.build(method: method, url: "https://host#{path}",
                             headers: Dexpace::Headers::EMPTY,)
    end

    def answer(handler, challenge, req = request)
      handler.authorization_for([challenge], req, proxy: false)
    end

    def params_of(header) = Challenges.parse(header).first.params

    def nc_of(handler, nonce) = params_of(answer(handler, digest(nonce: nonce, qop: "auth")))["nc"]
  end

  # AUTH-17: the four algorithms against the published vector and the derived expectations.
  class VectorsTest < DexpaceTestCase
    include Fixtures

    # RFC 2617 §3.5's vector IS a qop=auth value (nc=00000001, cnonce="0a4f113b"), so it is
    # asserted against a qop=auth challenge and a fixed cnonce.
    test "AUTH-17: RFC 2617 §3.5's MD5 qop=auth vector reproduces exactly" do
      header = answer(handler(mufasa, cnonce_source: fixed("0a4f113b")),
                      mufasa_challenge(qop: "auth,auth-int"),)
      fields = params_of(header)

      assert_equal(MD5_QOP_AUTH, fields["response"])
      assert_equal("00000001", fields["nc"])
      assert_equal("0a4f113b", fields["cnonce"])
      assert_equal("auth", fields["qop"])
      assert_equal("/dir/index.html", fields["uri"])
      assert_equal("5ccc069c403ebaf9f0171e9517f40e41", fields["opaque"])
      assert_equal("MD5", fields["algorithm"])
    end

    test "AUTH-17: the legacy RFC 2069 no-qop branch is H(HA1:nonce:HA2), a different value" do
      fields = params_of(answer(handler(mufasa), mufasa_challenge(qop: nil)))

      assert_equal(MD5_LEGACY, fields["response"])
      refute(fields.key?("qop")) # AUTH-22: cnonce, nc and qop only when qop is negotiated
      refute(fields.key?("nc"))
      refute(fields.key?("cnonce"))
    end

    test "AUTH-17: RFC 7616 §3.9.1's inputs under SHA-256 give the derived expectation" do
      header = answer(handler(jason, cnonce_source: fixed(RFC7616_CNONCE)),
                      jason_challenge("SHA-256"), request("/doe.json"),)
      fields = params_of(header)

      assert_equal(SHA256, fields["response"])
      assert_equal("SHA-256", fields["algorithm"])
      assert_equal(64, fields["response"].size)
    end

    test "AUTH-17: SHA-256-sess keys HA1 with the nonce and cnonce; the full spelling, bare" do
      header = answer(handler(jason, cnonce_source: fixed(RFC7616_CNONCE)),
                      jason_challenge("SHA-256-sess"), request("/doe.json"),)

      assert_equal(SHA256_SESS, params_of(header)["response"])
      assert_includes(header, "algorithm=SHA-256-sess,")
      refute_includes(header, 'algorithm="')
    end

    test "AUTH-17: MD5-sess follows the same session rule" do
      header = answer(handler(mufasa, cnonce_source: fixed("0a4f113b")),
                      mufasa_challenge(qop: "auth", algorithm: "MD5-sess"),)
      ha1 = Digest::MD5.hexdigest("Mufasa:testrealm@host.com:Circle Of Life")
      session_ha1 = Digest::MD5.hexdigest("#{ha1}:#{RFC2617_NONCE}:0a4f113b")
      ha2 = Digest::MD5.hexdigest("GET:/dir/index.html")
      expected = Digest::MD5.hexdigest("#{session_ha1}:#{RFC2617_NONCE}:00000001:0a4f113b:auth:#{ha2}")

      assert_equal(expected, params_of(header)["response"])
      assert_includes(header, "algorithm=MD5-sess,")
    end

    test "AUTH-17: every hash is lower-case hex of the selected algorithm" do
      md5 = params_of(answer(handler, digest(qop: "auth")))["response"]
      sha = params_of(answer(handler, digest(qop: "auth", algorithm: "SHA-256")))["response"]

      assert_match(/\A[0-9a-f]{32}\z/, md5)
      assert_match(/\A[0-9a-f]{64}\z/, sha)
    end
  end

  # AUTH-15, AUTH-16: which challenges are declined, and which is selected.
  class SelectionTest < DexpaceTestCase
    include Fixtures

    test "AUTH-15: an auth-int-only challenge is declined -- token-exact, never a substring" do
      declined = Challenges.parse(ChallengeFixtures::DIGEST_UNSUPPORTED_QOP)

      assert_nil(answer(handler, digest(qop: "auth-int")))
      assert_nil(handler.authorization_for(declined, request, proxy: false))
      refute_nil(answer(handler, digest(qop: "auth-int, auth")))
      refute_nil(answer(handler, digest(qop: "auth-int,AUTH")))
    end

    test "AUTH-15: an unsupported algorithm is declined; the four supported are accepted" do
      assert_nil(answer(handler, digest(algorithm: "SHA-512-256")))
      assert_nil(answer(handler, digest(algorithm: "SHA-512-256-sess")))
      DigestHandler::ALGORITHMS.each { |name| refute_nil(answer(handler, digest(algorithm: name))) }
      assert_equal(%w[MD5 MD5-sess SHA-256 SHA-256-sess], DigestHandler::ALGORITHMS)
    end

    test "AUTH-15: no mutual-auth verification -- nothing handles rspauth" do
      refute_respond_to(handler, :verify)
      refute_includes(File.read(LIB), "rspauth")
    end

    test "AUTH-16: satisfiable iff Digest (any case), realm and nonce present, qop auth/absent" do
      both = { "realm" => "r", "nonce" => "n" }

      refute_nil(answer(handler, Challenge.build(scheme: "DIGEST", params: both)))
      assert_nil(answer(handler, Challenge.build(scheme: "basic", params: both)))
      assert_nil(answer(handler, Challenge.build(scheme: "digest", params: { "nonce" => "n" })))
      assert_nil(answer(handler, Challenge.build(scheme: "digest", params: { "realm" => "r" })))
      assert_nil(handler.authorization_for([], request, proxy: false))
    end

    test "AUTH-16: an absent algorithm defaults to MD5; the token is matched case-insensitively" do
      assert_equal("MD5", params_of(answer(handler, digest))["algorithm"])
      assert_equal("SHA-256", params_of(answer(handler, digest(algorithm: "sha-256")))["algorithm"])
    end

    test "AUTH-16: selection prefers the algorithm earliest in the preference, whatever order" do
      offered = [digest(algorithm: "MD5"), digest(algorithm: "SHA-256")]
      prefers_sha = handler(credential, preference: %w[SHA-256 MD5])
      prefers_md5 = handler(credential, preference: %w[MD5 SHA-256])
      sha_only = handler(credential, preference: ["SHA-256"])

      assert_includes(prefers_sha.authorization_for(offered, request, proxy: false),
                      "algorithm=SHA-256,",)
      assert_includes(prefers_sha.authorization_for(offered.reverse, request, proxy: false),
                      "algorithm=SHA-256,",)
      assert_includes(prefers_md5.authorization_for(offered.reverse, request, proxy: false),
                      "algorithm=MD5,",)
      assert_nil(sha_only.authorization_for([digest(algorithm: "MD5")], request, proxy: false))
    end

    test "the preference must be a non-empty subset of the four; the source must answer #hex" do
      assert_raises(Dexpace::InvalidArgumentError) { handler(credential, preference: []) }
      assert_raises(Dexpace::InvalidArgumentError) do
        handler(credential, preference: %w[SHA-512-256])
      end
      assert_raises(Dexpace::InvalidArgumentError) do
        handler(credential, cnonce_source: Object.new)
      end
    end

    test "AUTH-14's rule at use: an empty username or password is refused at construction" do
      assert_raises(Dexpace::InvalidArgumentError) { handler(credential(username: "")) }
      assert_raises(Dexpace::InvalidArgumentError) { handler(credential(password: "")) }
      assert_raises(Dexpace::InvalidArgumentError) { handler("Mufasa:Circle Of Life") }
      handler(credential(password: " "))
    end
  end

  # AUTH-18, AUTH-19, AUTH-24: the per-nonce counter and its store.
  class CounterTest < DexpaceTestCase
    include Fixtures

    test "AUTH-18: nc starts at 00000001 per server nonce and increments only on reuse" do
      digest_handler = handler
      counts = [nc_of(digest_handler, "n1"), nc_of(digest_handler, "n1"),
                nc_of(digest_handler, "n2"), nc_of(digest_handler, "n1"),]

      assert_equal(%w[00000001 00000002 00000001 00000003], counts)
    end

    test "AUTH-18: exactly 8 lower-case hex digits, wrapping to the low 32 bits" do
      digest_handler = handler
      store = digest_handler.instance_variable_get(:@nonces)

      assert_kind_of(Dexpace.const_get(:BoundedMap), store)
      store.update("wrap") { |_current| 0xFFFFFFFF }

      assert_equal("00000000", nc_of(digest_handler, "wrap"))
      assert_equal("00000001", nc_of(digest_handler, "wrap"))
      store.update("big") { |_current| 0x1000000FE }

      assert_equal("000000ff", nc_of(digest_handler, "big"))
    end

    test "AUTH-19: bounded at the cap, 1024 by default; an evicted nonce restarts at 1" do
      assert_equal(1024, DigestHandler::DEFAULT_CAP)
      digest_handler = handler(credential, cap: 2)
      %w[a b c].each { |nonce| nc_of(digest_handler, nonce) } # "c" evicts "a"

      assert_equal(2, digest_handler.instance_variable_get(:@nonces).size)
      assert_equal("00000001", nc_of(digest_handler, "a"))
    end

    test "R11: the store is per handler instance, never shared" do
      one = handler
      two = handler
      nc_of(one, "n")

      assert_equal("00000001", nc_of(two, "n"))
      assert_equal("00000002", nc_of(one, "n"))
      refute_same(one.instance_variable_get(:@nonces), two.instance_variable_get(:@nonces))
    end

    # The deterministic proof that the increment is one critical section is
    # bounded_map_test.rb's forced interleaving, and the pin below is what ties the handler to
    # it: the store answers #update alone, so a read through #[] followed by #set -- two
    # critical sections, the lost-increment shape -- raises rather than surviving the race
    # under the GVL (review round 2's R2-2). The handler is frozen, so the store is reached
    # and narrowed in place, not replaced.
    test "AUTH-24: the increment is one BoundedMap#update, never a read through #[] then #set" do
      digest_handler = handler
      store = digest_handler.instance_variable_get(:@nonces)
      updates = []
      increment = store.method(:update)
      store.define_singleton_method(:update) do |key, &block|
        updates << key
        increment.call(key, &block)
      end
      %i[[] set put].each do |bypass|
        store.define_singleton_method(bypass) { |*| raise "the counter bypassed #update (AUTH-24)" }
      end

      assert_equal(%w[00000001 00000002], [nc_of(digest_handler, "n"), nc_of(digest_handler, "n")])
      assert_equal(%w[n n], updates)
    end

    # The handler-level property the pin above buys, seen end to end: sixteen threads reusing
    # one nonce produce sixteen hundred distinct counts.
    test "AUTH-24: sixteen threads reusing one nonce yield correct, non-duplicated counts" do
      digest_handler = handler
      barrier = ::Thread::Queue.new
      results = Array.new(16) { [] }
      threads = Array.new(16) do |index|
        Thread.new do
          barrier.pop
          100.times { results[index] << nc_of(digest_handler, "shared") }
        end
      end
      16.times { barrier << true }
      threads.each(&:join)
      counts = results.flatten

      assert_equal(1600, counts.uniq.size)
      assert_equal((1..1600).map { |n| format("%08x", n) }.sort, counts.sort)
    end

    test "AUTH-24: the handler is frozen and holds no per-request state" do
      assert_predicate(handler, :frozen?)
    end

    # The credential is materialised before the count is taken (the design's order), so the
    # one step that can raise leaves the nonce's counter where it was (review round 0's R0-4).
    test "AUTH-18: a refused attempt consumes no nonce count; the next response is not one high" do
      digest_handler = handler(credential(username: "a", password: "日"))

      assert_raises(Dexpace::Auth::UnencodableCredentialError) do
        answer(digest_handler, digest(nonce: "once", qop: "auth"))
      end
      assert_nil(digest_handler.instance_variable_get(:@nonces)["once"])
      header = answer(digest_handler, digest(nonce: "once", qop: "auth", charset: "UTF-8"))

      assert_equal("00000001", params_of(header)["nc"])
    end
  end

  # AUTH-20, AUTH-21: the cnonce source and the hash-input encoding.
  class EncodingTest < DexpaceTestCase
    include Fixtures

    test "AUTH-20: the cnonce is 16 SecureRandom bytes, hex-encoded, fresh per response" do
      source = fixed("a" * 32)
      answer(handler(credential, cnonce_source: source), digest(qop: "auth"))

      assert_equal([16], source.requests)
      live = handler
      cnonces = Array.new(5) { params_of(answer(live, digest(qop: "auth")))["cnonce"] }

      assert_equal(5, cnonces.uniq.size)
      cnonces.each { |cnonce| assert_match(/\A[0-9a-f]{32}\z/, cnonce) }
      assert_includes(File.read(LIB), "::SecureRandom")
      refute_match(/Random\.new|Random\.hex|Kernel#rand|\brand\(/, File.read(LIB))
    end

    test "AUTH-21: charset=UTF-8, in any case, hashes the UTF-8 bytes and never raises" do
      cred = credential(username: "a", password: "日")

      %w[UTF-8 utf-8 Utf-8].each do |charset|
        refute_nil(answer(handler(cred), digest(qop: "auth", charset: charset)))
      end
      expected_ha1 = Digest::MD5.hexdigest("a:r:日".b)
      header = answer(handler(cred, cnonce_source: fixed("c")),
                      digest(qop: "auth", charset: "UTF-8"),)
      ha2 = Digest::MD5.hexdigest("GET:/dir/index.html")
      expected = Digest::MD5.hexdigest("#{expected_ha1}:n:00000001:c:auth:#{ha2}")

      assert_equal(expected, params_of(header)["response"])
    end

    test "AUTH-21: no charset hashes ISO-8859-1 bytes of a representable credential" do
      cred = credential(username: "a", password: "café")
      header = answer(handler(cred, cnonce_source: fixed("c")), digest(qop: "auth"))
      latin1_ha1 = Digest::MD5.hexdigest("a:r:café".encode("ISO-8859-1"))
      ha2 = Digest::MD5.hexdigest("GET:/dir/index.html")
      expected = Digest::MD5.hexdigest("#{latin1_ha1}:n:00000001:c:auth:#{ha2}")

      assert_equal(expected, params_of(header)["response"])
      refute_equal(Digest::MD5.hexdigest("a:r:café"), latin1_ha1) # the two encodings differ
    end

    # R10's matrix, one assertion per algorithm: the raise is a property of the shared
    # encoding step, not of one hash routine.
    test "AUTH-21 (R10, P6-1): no charset and an unencodable password raise the typed failure" do
      cred = credential(username: "a", password: "日")
      DigestHandler::ALGORITHMS.each do |algorithm|
        error = assert_raises(Dexpace::Auth::UnencodableCredentialError) do
          answer(handler(cred), digest(qop: "auth", algorithm: algorithm))
        end

        assert_equal(:password, error.field)
        assert_equal("ISO-8859-1", error.encoding)
        assert_equal("UTF-8", error.source_encoding)
        assert_nil(error.cause)
        refute_includes(error.message, "日")
      end
    end

    # Ruby's conversion error names the offending character (`U+65E5 from UTF-8 to
    # ISO-8859-1`), which is a character of the password, and #full_message renders a cause on
    # every supported Ruby -- so the typed failure carries none, and the source encoding is a
    # member instead (review round 1's R1-3; 6c's P6-85).
    test "AUTH-8 (P6-85): no rendering of the failure carries a character of the secret" do
      error = assert_raises(Dexpace::Auth::UnencodableCredentialError) do
        answer(handler(credential(username: "a", password: "hunter日2")), digest)
      end
      renderings = [error.message, error.detailed_message, error.inspect,
                    error.full_message(highlight: false),
                    *Dexpace.each_cause(error).map(&:message),]

      assert_nil(error.cause)
      assert_equal(1, Dexpace.each_cause(error).count)
      renderings.each do |text|
        refute_includes(text, "U+65E5", text)
        refute_includes(text, "日", text)
        refute_includes(text, "hunter", text)
      end
      assert_includes(error.message, "from UTF-8")
    end

    test "AUTH-21 (R10): an unencodable username names :username" do
      error = assert_raises(Dexpace::Auth::UnencodableCredentialError) do
        answer(handler(credential(username: "日", password: "p")), digest)
      end

      assert_equal(:username, error.field)
    end

    # The UTF-8 branch can raise too, and when it does the error names UTF-8 and not Latin-1
    # (review round 0's R0-3): a BINARY-tagged credential has no UTF-8 meaning for a high byte,
    # and a UTF-8-tagged one with an invalid sequence passes `encode` to the same encoding
    # unvalidated, so it is refused on its own bytes rather than hashed as it is.
    test "AUTH-21 (R0-3): the UTF-8 branch's failure names UTF-8, for a BINARY or invalid tag" do
      binary = credential(username: "a", password: "p\xE4".b)
      error = assert_raises(Dexpace::Auth::UnencodableCredentialError) do
        answer(handler(binary), digest(charset: "UTF-8"))
      end

      assert_equal([:password, "UTF-8", "ASCII-8BIT"],
                   [error.field, error.encoding, error.source_encoding],)
      assert_nil(error.cause)
      refute_includes(error.full_message(highlight: false), "\\xE4") # the byte the cause named
      assert_includes(error.message, "advertised charset=UTF-8")
      refute_includes(error.message, "ISO-8859-1")
      invalid = credential(username: "a", password: (+"p\xE4").force_encoding(Encoding::UTF_8))
      error = assert_raises(Dexpace::Auth::UnencodableCredentialError) do
        answer(handler(invalid), digest(charset: "utf-8"))
      end

      assert_equal([:password, "UTF-8", "UTF-8"],
                   [error.field, error.encoding, error.source_encoding],)
      assert_nil(error.cause)
      latin1 = credential(username: "a", password: "pä".encode(Encoding::ISO_8859_1))

      refute_nil(answer(handler(latin1), digest(charset: "UTF-8"))) # transcoded, not refused
    end
  end

  # AUTH-22 and the two wire forms the port decided.
  class WireTest < DexpaceTestCase
    include Fixtures

    test "AUTH-22: username, realm, nonce, uri, response, cnonce, opaque quoted; three bare" do
      header = answer(handler(credential(username: "u", password: "p"), cnonce_source: fixed("cn")),
                      digest(qop: "auth", opaque: "op"),)

      %w[username realm nonce uri response cnonce opaque].each do |name|
        assert_match(/\b#{name}="[^"]*"/, header, name)
      end
      %w[qop nc algorithm].each do |name|
        assert_match(/\b#{name}=[^"]/, header, name)
        refute_match(/\b#{name}="/, header, name)
      end
      assert_match(/\ADigest /, header)
    end

    test "AUTH-22: embedded quotes and backslashes in an echoed value are backslash-escaped" do
      header = answer(handler(credential(username: 'u"v\\w', password: "p")),
                      digest(realm: 'r"ealm', nonce: "n", opaque: 'o\\p'),)

      assert_includes(header, 'username="u\\"v\\\\w"')
      assert_includes(header, 'realm="r\\"ealm"')
      assert_includes(header, 'opaque="o\\\\p"')
      assert_equal('r"ealm', params_of(header)["realm"]) # round-trips through the parser
    end

    test "AUTH-22: the digest-uri is the request-target: raw path, / when empty, plus ?query" do
      assert_equal("/", params_of(answer(handler, digest, request("")))["uri"])
      assert_equal("/a%20b?q=1&r=%2F",
                   params_of(answer(handler, digest, request("/a%20b?q=1&r=%2F")))["uri"],)
      assert_equal("/p", params_of(answer(handler, digest, request("/p#frag")))["uri"])
    end

    test "AUTH-17: the request method enters HA2, so POST and GET differ" do
      get = answer(handler(credential, cnonce_source: fixed("c")), digest(qop: "auth"))
      post = answer(handler(credential, cnonce_source: fixed("c")), digest(qop: "auth"),
                    request(method: "POST"),)

      refute_equal(params_of(get)["response"], params_of(post)["response"])
    end

    # HTTP-18's outbound grammar refuses a byte above 0x7F, so RFC 7616 §3.9.1's quoted
    # username cannot be sent as the RFC prints it; §3.4's username* form is the wire form.
    test "RFC 7616 §3.4: a non-ASCII username goes on the wire as username*=UTF-8''pct-encoded" do
      header = answer(handler(jason, cnonce_source: fixed(RFC7616_CNONCE)),
                      jason_challenge("SHA-256"), request("/doe.json"),)

      assert_includes(header, "username*=UTF-8''J%C3%A4s%C3%B8n%20Doe")
      refute_includes(header, 'username="')
      assert_predicate(header, :ascii_only?)
      assert_equal(SHA256, params_of(header)["response"]) # the hash still uses the raw username
      https_request.with(headers: https_request.headers.new_builder.set("Authorization",
                                                                        header,).build)
    end

    test "a challenge whose realm, nonce or opaque cannot be echoed under HTTP-18 is declined" do
      assert_nil(answer(handler, digest(realm: "caf\xC3\xA9".b)))
      assert_nil(answer(handler, digest(nonce: "n\x00".b)))
      assert_nil(answer(handler, digest(opaque: "日")))
      refute_nil(answer(handler, digest(realm: "plain realm", opaque: "ok")))
    end
  end
end
