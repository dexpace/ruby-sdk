# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Reusable WWW-Authenticate / Proxy-Authenticate header values for the phase-6c suites: RFC
# 2617 §3.5's Basic and MD5 challenges, RFC 7616 §3.9.1's SHA-256-sess challenge, one Digest
# challenge the handler must decline, and one deliberately malformed string per AUTH-13 recovery
# clause. Top level, one module, like every double under test/support/.
module ChallengeFixtures
  BASIC = 'Basic realm="example"'
  DIGEST_MD5 = 'Digest realm="testrealm@host.com", qop="auth,auth-int", ' \
               'nonce="dcd98b7102dd2f0e8b11d0f600bfb0c093", ' \
               'opaque="5ccc069c403ebaf9f0171e9517f40e41"'
  DIGEST_SHA256_SESS = 'Digest realm="http-auth@example.org", qop="auth", ' \
                       "algorithm=SHA-256-sess, " \
                       'nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v", ' \
                       'opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS", charset=UTF-8, ' \
                       "userhash=false"
  DIGEST_UNSUPPORTED_QOP = 'Digest realm="r", qop="auth-int", nonce="n"'
  MALFORMED_UNTERMINATED_QUOTE = 'Digest realm="unterminated'
  MALFORMED_STRAY_COMMA = "Digest realm=r,,nonce=n"
  MALFORMED_VALUE = 'Digest realm=@@, nonce="n"'
  BARE_TOKEN68 = "Bearer dGhlIHNlY3JldCB0b2tlbg=="
end
