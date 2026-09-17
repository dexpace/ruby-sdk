# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"
require "uri"
require_relative "../support/fake_config_source"
require_relative "../support/warning_capture"

# CFG-22 (the model's masking), CFG-23 and CFG-27 (bypass), and the resolver behind
# Dexpace::Proxy.resolve: CFG-24 (precedence and never-throw), CFG-25 (the explicit port), CFG-26
# (the non-proxy list), CFG-27 (bypass-all) and CFG-28 (explicit resolution only). The resolver
# is Dexpace::ProxyResolution, a private_constant with no test mirror, asserted here at its one
# call site.
#
# testing/26b866e1 forbids assert_nothing_raised, so CFG-24's never-throw clause is asserted as
# assert_nil on the result AND an assertion on the captured warning. The second half is not
# optional: DexpaceTestCase turns a warning into a failure, and WarningCapture.record -- phase 2's
# one mechanism for observing a Kernel#warn -- is how the required warning is observed instead.
#
# Both seams are always supplied: Configuration.build defaults env_source: to the real process
# environment, and a proxy suite that inherits it fails on a developer machine with HTTPS_PROXY set.
module ProxyTest
  # Resolves against a hermetic configuration built from the two maps.
  def self.resolve(properties: {}, environment: {})
    Dexpace::Proxy.resolve(Dexpace::Configuration.build(
                             env_source: FakeConfigSource.new(environment),
                             property_source: FakeConfigSource.new(properties),
                           ))
  end

  # Resolves inside a warning capture; returns the proxy (or nil) and the warnings emitted.
  def self.resolve_warning(properties: {}, environment: {})
    proxy = :unset
    warnings = WarningCapture.record do
      proxy = resolve(properties: properties, environment: environment)
    end
    [proxy, warnings]
  end

  # CFG-22, CFG-23 and CFG-27 on the model.
  class ModelTest < DexpaceTestCase
    def proxy(**extra)
      Dexpace::Proxy.build(type: Dexpace::Proxy::Type::HTTP, host: "proxy.internal", port: 8080,
                           **extra,)
    end

    test "CFG-22 / P5-7: #to_s and #inspect both mask the password; the username is kept" do
      secret = "SuperSecretPassword"
      masked = proxy(username: "admin", password: secret)

      refute_includes(masked.to_s, secret)
      refute_includes(masked.inspect, secret)
      assert_equal("http://admin:****@proxy.internal:8080", masked.to_s)
      assert_includes(masked.inspect, 'password="****"')
      assert_includes(masked.inspect, 'username="admin"')
      assert_equal("http://proxy.internal:8080", proxy.to_s)
      assert_includes(proxy.inspect, "password=nil")
      assert_includes(proxy(challenge_handler: -> {}).inspect, 'challenge_handler="Proc"')
    end

    test "CFG-22: every member is read back, frozen, the type resolved through Type.of" do
      built = proxy(type: "socks5", username: "u", password: "p", bypass_all: true,
                    non_proxy_hosts: [Dexpace::Proxy::HostPattern.of("*.local")],)

      assert_same(Dexpace::Proxy::Type::SOCKS5, built.type)
      assert_equal("proxy.internal", built.host)
      assert_equal(8080, built.port)
      assert_equal(["*.local"], built.non_proxy_hosts.map(&:glob))
      assert_predicate(built.non_proxy_hosts, :frozen?)
      assert_predicate(built, :frozen?)
      assert_predicate(built.host, :frozen?)
      assert_predicate(built.password, :frozen?)
      assert_same(true, built.bypass_all)
      assert_nil(built.challenge_handler)
      refute_respond_to(Dexpace::Proxy, :new)
    end

    test "CFG-23 / CFG-27: #bypass? short-circuits on bypass_all, else any pattern decides" do
      patterns = %w[*.local 127.0.0.1].map { |glob| Dexpace::Proxy::HostPattern.of(glob) }
      listed = proxy(non_proxy_hosts: patterns)

      assert(listed.bypass?("service.local"))
      assert(listed.bypass?("SERVICE.LOCAL"))
      assert(listed.bypass?("127.0.0.1"))
      refute(listed.bypass?("external.com"))
      refute(proxy.bypass?("service.local"))
      assert(proxy(bypass_all: true).bypass?("anything.com"))
    end

    test "CFG-25 / CFG-37: the model refuses an absent, non-Integer or out-of-range port" do
      assert_raises(Dexpace::InvalidArgumentError) { proxy(port: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { proxy(port: "8080") }
      assert_raises(Dexpace::InvalidArgumentError) { proxy(port: -1) }
      assert_raises(Dexpace::InvalidArgumentError) { proxy(port: 65_536) }
      assert_equal(0, proxy(port: 0).port)
      assert_equal(65_535, proxy(port: 65_535).port)
    end

    test "CFG-37: the model refuses a blank host, an unknown type and a non-pattern entry" do
      assert_raises(Dexpace::InvalidArgumentError) { proxy(host: " ") }
      assert_raises(Dexpace::InvalidArgumentError) { proxy(host: nil) }
      assert_raises(Dexpace::InvalidArgumentError) { proxy(type: "ftp") }
      assert_raises(Dexpace::InvalidArgumentError) { proxy(non_proxy_hosts: ["*.local"]) }
      assert_raises(Dexpace::InvalidArgumentError) { proxy(non_proxy_hosts: nil) }
    end

    test "HTTP-3 / CFG-8: #with re-validates through .build and the pattern list is a copy" do
      list = [Dexpace::Proxy::HostPattern.of("*.local")]
      built = proxy(non_proxy_hosts: list)
      list << Dexpace::Proxy::HostPattern.of("*.late")

      assert_equal(1, built.non_proxy_hosts.size)
      assert_equal(9090, built.with(port: 9090).port)
      assert_raises(Dexpace::InvalidArgumentError) { built.with(port: 70_000) }
    end
  end

  # CFG-24 and CFG-25: the system-property layer, and its boundary with the environment.
  class PropertyLayerTest < DexpaceTestCase
    # The chapter's own conformance case, and a negative: set ONLY the http.* host and port plus
    # the https.* credentials, and assert the resolved proxy carries those credentials. A test
    # that also sets https.proxyHost proves nothing, because the cross-layer read is the point.
    test "CFG-24: the port comes from the host's own layer, and credentials from https.* only" do
      properties = {
        "http.proxyHost" => "http-proxy.corp", "http.proxyPort" => "3128",
        "https.proxyUser" => "alice", "https.proxyPassword" => "secret",
      }
      proxy = ProxyTest.resolve(properties: properties)

      assert_equal("http-proxy.corp", proxy.host)
      assert_equal(3128, proxy.port)
      assert_equal("alice", proxy.username)
      assert_equal("secret", proxy.password)
      assert_same(Dexpace::Proxy::Type::HTTP, proxy.type)
    end

    test "CFG-24: http.proxyUser and http.proxyPassword are never read -- no http.* fallback" do
      properties = {
        "http.proxyHost" => "http-proxy.corp", "http.proxyPort" => "3128",
        "http.proxyUser" => "bob", "http.proxyPassword" => "nope",
      }
      proxy = ProxyTest.resolve(properties: properties)

      assert_nil(proxy.username)
      assert_nil(proxy.password)
    end

    test "CFG-24: https.proxyHost wins over http.proxyHost and takes https.proxyPort with it" do
      properties = {
        "https.proxyHost" => "secure.corp", "https.proxyPort" => "8443",
        "http.proxyHost" => "plain.corp", "http.proxyPort" => "3128",
      }
      proxy = ProxyTest.resolve(properties: properties)

      assert_equal("secure.corp", proxy.host)
      assert_equal(8443, proxy.port)
    end

    # The clause most likely to be written as two independent reads: a host under https.* with
    # only http.proxyPort set is a MISSING port, never a borrowed one.
    test "CFG-24 / CFG-25: the port is never borrowed from the other layer" do
      properties = {
        "https.proxyHost" => "secure.corp", "http.proxyPort" => "3128",
      }
      proxy, warnings = ProxyTest.resolve_warning(properties: properties)

      assert_nil(proxy)
      assert_equal(1, warnings.size)
      assert_includes(warnings.first, "secure.corp")
      assert_includes(warnings.first, "https.proxyPort")
    end

    test "CFG-25: a port outside 0..65535, non-numeric or blank yields nil with a warning" do
      ["65536", "70000", "-1", "abc", "", " ", "80.5", "0x50"].each do |port|
        properties = {
          "https.proxyHost" => "proxy.corp", "https.proxyPort" => port,
        }
        proxy, warnings = ProxyTest.resolve_warning(properties: properties)

        assert_nil(proxy, port.inspect)
        assert_equal(1, warnings.size, port.inspect)
        assert_includes(warnings.first, "proxy.corp")
        assert_includes(warnings.first, "[dexpace]")
        # The resolver's OWN range check answered, not the model's refusal caught by the backstop
        # -- which is the guard a resolver accepting 65536 fails, since Proxy.build still refuses.
        assert_includes(warnings.first, "outside 0..65535")
      end
    end

    # CFG-24's clause (2) is "IF NO system-property host is set". A property host whose port is
    # unusable therefore yields nil; falling through to HTTPS_PROXY would turn CFG-25's "MUST
    # yield null rather than guessing a default port" into guessing a different proxy.
    test "CFG-24 / CFG-25: an unusable property port does not fall through to the environment" do
      proxy, warnings = ProxyTest.resolve_warning(
        properties: { "https.proxyHost" => "proxy.corp", "https.proxyPort" => "abc" },
        environment: { "HTTPS_PROXY" => "http://other.example:8080" },
      )

      assert_nil(proxy)
      assert_equal(1, warnings.size)
    end

    test "CFG-25: the boundary ports 0 and 65535 are explicit and accepted" do
      [0, 65_535].each do |port|
        properties = {
          "https.proxyHost" => "proxy.corp", "https.proxyPort" => port.to_s,
        }
        proxy = ProxyTest.resolve(properties: properties)

        assert_equal(port, proxy.port)
      end
    end

    test "CFG-24: a blank property host is absent, and the environment is consulted instead" do
      proxy = ProxyTest.resolve(
        properties: { "https.proxyHost" => "  ", "https.proxyPort" => "1" },
        environment: { "HTTP_PROXY" => "http://env.example:8080" },
      )

      assert_equal("env.example", proxy.host)
    end

    # §8.2's substituted third source IS Dexpace.configure, and every other case here injects a
    # FakeConfigSource, which proves the resolver and nothing about the tier production reads. So
    # exactly one case drives the slot end to end: a #property that folded its key would resolve
    # nil here while every fake-driven case still passed.
    test "CFG-24 / §10.16: a proxy configured through Dexpace.configure resolves from the slot" do
      Dexpace.configure do |c|
        c.env_source = FakeConfigSource.new
        c.property("https.proxyHost", "secure.corp")
        c.property("https.proxyPort", "8443")
        c.property("https.proxyUser", "alice")
        c.property("https.proxyPassword", "secret")
      end

      proxy = Dexpace::Proxy.resolve

      assert_equal("secure.corp", proxy.host)
      assert_equal(8443, proxy.port)
      assert_equal("alice", proxy.username)
      assert_equal("secret", proxy.password)
    ensure
      Dexpace.reset_config!
    end
  end

  # CFG-24 and CFG-25: the environment URL.
  class EnvironmentLayerTest < DexpaceTestCase
    test "CFG-24: HTTPS_PROXY wins over HTTP_PROXY, parsed as scheme://user:pass@host:port" do
      environment = {
        "HTTPS_PROXY" => "socks5://alice:secret@secure.example:1080",
        "HTTP_PROXY" => "http://plain.example:3128",
      }
      proxy = ProxyTest.resolve(environment: environment)

      assert_same(Dexpace::Proxy::Type::SOCKS5, proxy.type)
      assert_equal("secure.example", proxy.host)
      assert_equal(1080, proxy.port)
      assert_equal("alice", proxy.username)
      assert_equal("secret", proxy.password)
    end

    test "CFG-24: the scheme selects the type -- socks4, socks5, and everything else HTTP" do
      types = { "socks4://h:1" => Dexpace::Proxy::Type::SOCKS4,
                "SOCKS5://h:1" => Dexpace::Proxy::Type::SOCKS5,
                "http://h:1" => Dexpace::Proxy::Type::HTTP,
                "https://h:1" => Dexpace::Proxy::Type::HTTP, }
      types.each do |url, type|
        proxy = ProxyTest.resolve(environment: { "HTTP_PROXY" => url })

        assert_same(type, proxy.type, url)
      end
    end

    # A guard, not a coincidence: the day someone "simplifies" the resolver onto #port, this says
    # why it is wrong rather than merely failing somewhere else.
    test "CFG-25: RFC3986_PARSER#port defaults an absent port to 80 and #split[3] does not" do
      assert_equal(80, URI::RFC3986_PARSER.parse("http://proxy.example").port)
      assert_nil(URI::RFC3986_PARSER.split("http://proxy.example")[3])
      assert_equal("8080", URI::RFC3986_PARSER.split("http://proxy.example:8080")[3])
    end

    test "CFG-25: a proxy URL with no explicit port is invalid: nil, with a warning naming it" do
      ["http://proxy.example", "https://proxy.example/", "http://u:p@proxy.example"].each do |url|
        proxy, warnings = ProxyTest.resolve_warning(environment: { "HTTPS_PROXY" => url })

        assert_nil(proxy, url)
        assert_equal(1, warnings.size, url)
        assert_includes(warnings.first, "no explicit port")
      end
    end

    test "CFG-24 / CFG-25: a malformed proxy URL yields nil with a warning and never raises" do
      ["http://h:abc", "not a url", "http://:8080", "http://h:70000", "://h:1", "http://h:-1",
       "http:// h:1", "%zz://h:1",].each do |bad|
        proxy, warnings = ProxyTest.resolve_warning(environment: { "HTTPS_PROXY" => bad })

        assert_nil(proxy, bad.inspect)
        assert_equal(1, warnings.size, bad.inspect)
        # Each is answered by its own explicit branch, never by the backstop.
        refute_includes(warnings.first, "resolution failed", bad.inspect)
      end
    end

    # The backstop: CFG-24's clause is about the operation, so a seam that raises from inside
    # the resolution is answered the same way as a malformed value -- nil and one warning.
    test "CFG-24: a seam that raises inside the resolution yields nil with a warning, no raise" do
      raising = ->(_key) { raise ::IOError, "seam exploded" }
      configuration = Dexpace::Configuration.build(env_source: raising, property_source: raising)
      proxy = :unset
      warnings = WarningCapture.record { proxy = Dexpace::Proxy.resolve(configuration) }

      assert_nil(proxy)
      assert_equal(1, warnings.size)
      assert_includes(warnings.first, "proxy resolution failed: IOError: seam exploded")
    end

    test "CFG-24: a blank environment URL is absent, not malformed, and warns nothing" do
      assert_nil(ProxyTest.resolve(environment: { "HTTPS_PROXY" => "   " }))
      assert_nil(ProxyTest.resolve)
    end

    test "CFG-24: percent-encoded credentials are decoded, and + is not a space" do
      environment = {
        "HTTPS_PROXY" => "http://u%40x:p%3As+t@proxy.example:8080",
      }
      proxy = ProxyTest.resolve(environment: environment)

      assert_equal("u@x", proxy.username)
      assert_equal("p:s+t", proxy.password)
    end

    test "CFG-24: a username with no password, and no userinfo at all, leave the slots nil" do
      with_user = ProxyTest.resolve(environment: { "HTTPS_PROXY" => "http://alice@p.example:8080" })

      assert_equal("alice", with_user.username)
      assert_nil(with_user.password)

      bare = ProxyTest.resolve(environment: { "HTTPS_PROXY" => "http://proxy.example:8080" })

      assert_nil(bare.username)
      assert_nil(bare.password)
    end
  end

  # CFG-26, CFG-27 and CFG-28.
  class NonProxyTest < DexpaceTestCase
    def resolve(environment: {}, properties: {})
      ProxyTest.resolve(
        environment: { "HTTP_PROXY" => "http://proxy.example:8080" }.merge(environment),
        properties: properties,
      )
    end

    def globs(environment: {}, properties: {})
      resolve(environment: environment, properties: properties).non_proxy_hosts.map(&:glob)
    end

    test "CFG-26: NO_PROXY splits on unescaped commas -- split, drop empty, unescape, trim" do
      # The whitespace-only fragment survives CFG-26's order as an empty token and is then
      # dropped, because an empty glob is not a host pattern.
      assert_equal(["a,b", "c", "d"], globs(environment: { "NO_PROXY" => "a\\,b, c, , d" }))
    end

    test "CFG-26: the chapter's own conformance outputs" do
      assert_equal(["a,b", "c"], globs(environment: { "NO_PROXY" => "a\\,b,c" }))
      assert_equal(["a|b", "c"], globs(properties: { "http.nonProxyHosts" => "a\\|b|c" }))
      assert_equal(%w[a c], globs(environment: { "NO_PROXY" => "a,,c" }))
      assert_equal(["a"], globs(environment: { "NO_PROXY" => "a," }))
    end

    test "CFG-26: http.nonProxyHosts (pipe-separated) beats NO_PROXY, whichever gave the host" do
      proxy = resolve(
        properties: { "http.nonProxyHosts" => "a\\|b|*.internal" },
        environment: { "HTTPS_PROXY" => "http://proxy.example:8080",
                       "NO_PROXY" => "ignored.example", },
      )

      assert_equal(["a|b", "*.internal"], proxy.non_proxy_hosts.map(&:glob))
      assert(proxy.bypass?("svc.internal"))
      refute(proxy.bypass?("ignored.example"))
    end

    test "CFG-26: the separators are not interchangeable across the two sources" do
      assert_equal(["a|b"], globs(environment: { "NO_PROXY" => "a|b" }))
      assert_equal(["a,b"], globs(properties: { "http.nonProxyHosts" => "a,b" }))
    end

    test "CFG-27: exactly one bare * is bypass-all and yields nil; inside a list it is a glob" do
      assert_nil(resolve(environment: { "NO_PROXY" => "*" }))
      assert_nil(resolve(environment: { "NO_PROXY" => " * " }))
      assert_nil(resolve(properties: { "http.nonProxyHosts" => "*" }))

      proxy = resolve(environment: { "NO_PROXY" => "*,x.example" })

      refute_nil(proxy)
      refute_predicate(proxy, :bypass_all)
      assert_equal(["*", "x.example"], proxy.non_proxy_hosts.map(&:glob))
      assert(proxy.bypass?("anything.at.all"))
    end

    test "CFG-26: an empty or absent non-proxy source yields an empty, frozen pattern list" do
      assert_empty(resolve.non_proxy_hosts)
      assert_empty(resolve(environment: { "NO_PROXY" => "" }).non_proxy_hosts)
      assert_empty(resolve(environment: { "NO_PROXY" => " , , " }).non_proxy_hosts)
      assert_predicate(resolve.non_proxy_hosts, :frozen?)
    end

    # CFG-28's MAY is taken and its prohibition met structurally: resolution happens only when a
    # caller invokes the resolver, and nothing in core invokes it -- the absence of a call site is
    # the enforcement. The default argument is the process-wide slot.
    test "CFG-28: nothing in core resolves proxy configuration implicitly" do
      root = File.expand_path("../../lib", __dir__)
      call_sites = Dir.glob("#{root}/**/*.rb").select do |path|
        File.readlines(path).grep_v(/\A\s*#/).any? { |line| line.include?("Proxy.resolve") }
      end

      assert_empty(call_sites)
      assert_nil(Dexpace::Proxy.resolve) # the empty slot, and no ENV read that a fake could see
    end

    test "CFG-37 / P2-15: .resolve requires a Configuration; the resolver is a private constant" do
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy.resolve(nil) }
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Proxy.resolve(:cfg) }
      assert_raises(::NameError) { ::Dexpace::ProxyResolution }
      refute_includes(Dexpace.constants, :ProxyResolution)
    end
  end
end
