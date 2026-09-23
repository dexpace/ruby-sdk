# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# The InvariantSuite assertions whose subject is a CORE CONSTANT, proven against deliberately
# defective stand-in cores. Each double is a Module.new carrying exactly the constants its
# assertion probes, defective in exactly the clause the assertion names -- which is what shows the
# assertion discriminates rather than merely passing against the real tree.
# XCUT-4, XCUT-5, XCUT-6, XCUT-7, XCUT-8, XCUT-9, XCUT-10, XCUT-16, XCUT-18, XCUT-19, XCUT-20,
# XCUT-21, XCUT-23, XCUT-24.
class DexpaceConformanceInvariantSuiteCoreTest < DexpaceTestCase # rubocop:disable Metrics/ClassLength -- one defective stand-in core per assertion, each beside the test that drives it
  Suite = Dexpace::Conformance::InvariantSuite

  def statuses(report)
    report.results.each_with_object({}) { |r, h| (h[r.assertion.ids.first] ||= []) << r.status }
  end

  # A defective core: the real Dexpace with one constant replaced. The overrides are real
  # constants on a fresh module, and `const_missing` falls through to core -- which is what makes
  # BOTH spellings work, `core::Thing` and `core.const_get(:Thing)`, since Ruby routes each
  # through `const_missing` when the name is not defined locally. Every OTHER assertion therefore
  # reaches the real thing, so one test changes one subject.
  def patched(**overrides)
    real = ::Dexpace
    Module.new do
      overrides.each { |name, value| const_set(name, value) }
      define_singleton_method(:const_missing) { |name| real.const_get(name) }
      define_singleton_method(:const_defined?) do |name, *|
        super(name, false) || real.const_defined?(name)
      end
      define_singleton_method(:respond_to_missing?) { |name, _| real.respond_to?(name) }
      define_singleton_method(:method_missing) do |name, *args, &block|
        real.public_send(name, *args, &block)
      end
    end
  end

  # ---- XCUT-4 ----

  test "a transport error outside the IOError family fails XCUT-4" do
    outside = Class.new(::StandardError) { def retryable? = true }
    report = Suite.run(core: patched(TransportError: outside))

    assert_equal([:failed], statuses(report)["XCUT-4"])
  end

  test "a transport error that is not always-retryable fails XCUT-4" do
    lying = Class.new(::IOError) do
      include Dexpace::Error

      def retryable? = false
    end
    report = Suite.run(core: patched(TransportError: lying))

    assert_equal([:failed], statuses(report)["XCUT-4"])
  end

  # ---- XCUT-5 ----

  test "a status classifier missing a 5xx fails XCUT-5, which a {500,502,503,504} list would" do
    narrow = Module.new do
      def self.retryable_status?(code) = [408, 429, 500, 502, 503, 504].include?(code)
    end
    report = Suite.run(core: patched(Retryability: narrow))

    assert_equal([:failed], statuses(report)["XCUT-5"],
                 "507 is a 5xx outside 501 and 505, so the classifier must call it retryable",)
  end

  test "a classifier that calls 501 retryable fails XCUT-5" do
    wide = Module.new do
      def self.retryable_status?(code)
        code >= 500 || [408, 429].include?(code)
      end
    end

    assert_equal([:failed], statuses(Suite.run(core: patched(Retryability: wide)))["XCUT-5"])
  end

  # ---- XCUT-8 ----

  test "a factory that fabricates an error for a 2xx fails XCUT-8" do
    permissive = Class.new(::StandardError) do
      def self.for(response) = new(response.status.code.to_s)
      def self.for_or_nil(_response) = nil
    end
    report = Suite.run(core: patched(ProtocolError: permissive))

    assert_equal([:failed], statuses(report)["XCUT-8"])
  end

  test "a convenience form that returns an error for a non-error status fails XCUT-8" do
    eager = Class.new(Dexpace::ProtocolError) { def self.for_or_nil(_response) = allocate }

    assert_equal([:failed], statuses(Suite.run(core: patched(ProtocolError: eager)))["XCUT-8"])
  end

  # ---- XCUT-9 ----

  # A two-node cycle could not tell these apart from a conforming walk, which is why the fixture
  # is three nodes.
  test "a DEPTH-CAPPED cause walk fails XCUT-9" do
    capped = Module.new do
      def self.each_cause(error)
        return enum_for(:each_cause, error) unless block_given?

        current = error
        2.times do
          break if current.nil?

          yield current
          current = current.cause
        end
      end
    end

    assert_equal([:failed], statuses(Suite.run(core: capped))["XCUT-9"])
  end

  test "a NON-TERMINATING cause walk reports failed rather than hanging the suite" do
    looping = Module.new do
      def self.each_cause(error)
        return enum_for(:each_cause, error) unless block_given?

        current = error
        loop do
          yield current
          current = current.cause
        end
      end
    end

    assert_equal([:failed], statuses(Suite.run(core: looping))["XCUT-9"])
  end

  # ---- XCUT-20 ----

  test "a redactor that throws on a malformed URL fails XCUT-20" do
    throwing = Class.new do
      def url(_value) = raise("boom")
      def header_value(_name, value) = value
      def header_name?(_name) = false
    end
    instrumentation = Module.new do
      const_set(:Redactor, Class.new { const_set(:DEFAULT, throwing.new) })
      const_set(:Logger, Dexpace::Instrumentation::Logger)
      const_set(:Preview, Dexpace::Instrumentation::Preview)
      define_singleton_method(:contain) { |*a, **k, &b| Dexpace::Instrumentation.contain(*a, **k, &b) }
    end
    report = Suite.run(core: patched(Instrumentation: instrumentation))

    assert_equal([:error], statuses(report)["XCUT-20"],
                 "an observability path that throws reaches Runner's bare rescue, which is " \
                 "exactly the signal XCUT-20 forbids in a caller's request path",)
  end

  # ---- XCUT-23 ----

  test "a registry that silently picks one of two candidates fails XCUT-23" do
    silent = Class.new do
      # rubocop:disable Lint/UnusedMethodArgument -- phase 2's filed Registry signatures
      def initialize(seam:, installer:, conforms:) = (@factories = {})
      def register(key, factory, core:) = (@factories[key] = factory)
      # rubocop:enable Lint/UnusedMethodArgument
      def install(provider) = (@installed = provider)
      def resolve = @installed || @factories.values.first&.call
    end
    report = Suite.run(core: patched(Registry: silent))

    assert_equal([:failed], statuses(report)["XCUT-23"])
  end

  test "a registry whose discovery beats an explicit install fails XCUT-23" do
    inverted = Class.new do
      # rubocop:disable Lint/UnusedMethodArgument -- phase 2's filed Registry signatures; only
      # `installer:` is read here, and the rest are the shape the suite calls.
      def initialize(seam:, installer:, conforms:)
        @installer = installer
        @factories = {}
      end

      def register(key, factory, core:) = (@factories[key] = factory)
      # rubocop:enable Lint/UnusedMethodArgument
      def install(provider) = (@installed = provider)

      def resolve
        raise "no candidate; install through #{@installer}" if @factories.empty? && @installed.nil?
        raise "two candidates; install through #{@installer}" if @factories.size > 1

        @factories.values.first&.call || @installed
      end
    end
    report = Suite.run(core: patched(Registry: inverted))

    assert_equal([:failed], statuses(report)["XCUT-23"],
                 "the ORDERING is the content: failing loudly on ambiguity is two of three",)
  end

  # ---- XCUT-21, through the driver's cnonce factory ----

  def digest_core(&)
    handler = Class.new(&)
    patched(Auth: Module.new do
      const_set(:DigestHandler, handler)
      define_singleton_method(:const_missing) { |name| ::Dexpace::Auth.const_get(name) }
    end)
  end

  def x21(core)
    handler = core.const_get(:Auth).const_get(:DigestHandler)
    Suite.run(core: core, cnonce: ->(source) { handler.new(:cred, cnonce_source: source).cnonce })
  end

  test "a handler with no injectable cnonce source fails XCUT-21" do
    core = digest_core do
      def initialize(credential) = (@credential = credential)
      def cnonce = format("%032x", rand(2**128))
    end
    handler = core.const_get(:Auth).const_get(:DigestHandler)
    report = Suite.run(core: core, cnonce: ->(_source) { handler.new(:cred).cnonce })

    assert_equal([:failed], statuses(report)["XCUT-21"])
  end

  test "a 128-bit draw truncated to eight characters fails XCUT-21" do
    core = digest_core do
      def initialize(credential, cnonce_source: ::SecureRandom)
        @credential = credential
        @source = cnonce_source
      end

      def cnonce = @source.hex(16)[0, 8]
    end

    assert_equal([:failed], statuses(x21(core))["XCUT-21"],
                 "a character count called this conforming and urlsafe_base64(16) not",)
  end

  test "a conforming handler passes XCUT-21 whatever encoding renders its 128 bits" do
    core = digest_core do
      def initialize(credential, cnonce_source: ::SecureRandom)
        @credential = credential
        @source = cnonce_source
      end

      def cnonce = @source.urlsafe_base64(16)
    end

    assert_equal([:passed], statuses(x21(core))["XCUT-21"])
  end

  # ---- XCUT-18's call-site assertion ----

  # A conforming adapter: it re-runs HTTP-17/HTTP-18 before touching the wire.
  class RefusingTransport
    def call(request, _options, _cancellation)
      request.headers.each_entry do |name, value|
        ::Dexpace::HeaderSyntax.validate_name!(name)
        ::Dexpace::HeaderSyntax.validate_outbound_value!(value, name: name)
      end
      raise "unreachable: the forged name must have been refused"
    end
  end

  # A non-conforming adapter: it connects first and validates afterwards.
  class DispatchingTransport
    def call(request, _options, _cancellation)
      ::TCPSocket.new(request.url.host, request.url.port).close # wire activity before any check
      raise ::Dexpace::InvalidArgumentError, "too late: already on the wire"
    end
  end

  test "a transport that re-validates before dispatch passes XCUT-18's call-site assertion" do
    report = Suite.run(core: ::Dexpace, transport: -> { RefusingTransport.new })

    assert_equal(%i[passed passed], statuses(report)["XCUT-18"])
  end

  test "a transport that touches the wire before re-validating fails XCUT-18's call site" do
    report = Suite.run(core: ::Dexpace, transport: -> { DispatchingTransport.new })

    assert_equal(%i[passed failed], statuses(report)["XCUT-18"])
    assert_match(/accepted a connection/, report.failures.first.detail)
  end

  # ---- XCUT-16, through the driver's credential factory ----

  Sent = Struct.new(:headers)

  test "a credential path with no HTTPS guard fails XCUT-16" do
    unguarded = lambda do |url:, cross_origin: false| # rubocop:disable Lint/UnusedBlockArgument
      Sent.new(cross_origin ? {} : { "authorization" => "Bearer t" })
    end
    report = Suite.run(core: ::Dexpace, credential_hop: unguarded)

    assert_equal([:failed], statuses(report)["XCUT-16"])
  end

  test "a guard applied to the credential-FREE re-issue too fails XCUT-16's third clause" do
    over_eager = lambda do |url:, cross_origin: false|
      unless url.start_with?("https:")
        raise Dexpace::Auth::HTTPSRequiredError.new(scheme: "http",
                                                    step: "double",)
      end

      Sent.new(cross_origin ? {} : { "authorization" => "Bearer t" })
    end
    report = Suite.run(core: ::Dexpace, credential_hop: over_eager)

    assert_equal([:failed], statuses(report)["XCUT-16"],
                 "the guard applies ONLY on the credential-attaching path",)
  end

  test "a conforming credential path passes all three of XCUT-16's clauses" do
    conforming = lambda do |url:, cross_origin: false|
      next Sent.new({}) if cross_origin
      unless url.start_with?("https:")
        raise Dexpace::Auth::HTTPSRequiredError.new(scheme: "http",
                                                    step: "double",)
      end

      Sent.new({ "authorization" => "Bearer t" })
    end

    assert_equal([:passed],
                 statuses(Suite.run(core: ::Dexpace, credential_hop: conforming))["XCUT-16"],)
  end
end
