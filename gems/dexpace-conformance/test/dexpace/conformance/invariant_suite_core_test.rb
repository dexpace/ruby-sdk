# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# The InvariantSuite assertions whose subject is a CORE CONSTANT, proven against deliberately
# defective stand-in cores. Each double is a Module.new carrying exactly the constants its
# assertion probes, defective in exactly the clause the assertion names -- which is what shows the
# assertion discriminates rather than merely passing against the real tree.
# Every ID here is one this file really drives: XCUT-1, XCUT-2, XCUT-4, XCUT-5, XCUT-6, XCUT-7,
# XCUT-8, XCUT-9, XCUT-10, XCUT-16, XCUT-18, XCUT-19, XCUT-20, XCUT-21, XCUT-23 and XCUT-24. The
# list is kept honest deliberately: it named XCUT-6, XCUT-7 and XCUT-10 before any double for them
# existed, and a header claiming a double nobody wrote is what review round 2 caught.
# XCUT-3 and XCUT-12 have no double here and their checklist rows say so: either would need a
# subject that parks a thread past the assertion's own bound, which leaks the thread the base
# case's teardown counts. Their guards are subject mutations 22 and 23.
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

  # A defective Resilience namespace: the real one with the named constants replaced. Its own
  # `const_missing` falls through to `::Dexpace::Resilience`, so replacing `Policy` leaves
  # `RetrySettings` and `Resend` the real ones -- `patched`'s discipline one level down.
  def resilience_core(**overrides)
    patched(Resilience: Module.new do
      overrides.each { |name, value| const_set(name, value) }
      define_singleton_method(:const_missing) { |name| ::Dexpace::Resilience.const_get(name) }
    end)
  end

  # A defective Policy: the three classifier queries this suite reads, every one conforming except
  # the ones named. Written out rather than delegated through `method_missing`, because the point
  # of the double is that a reader can see which of the three is wrong.
  def policy_core(**broken)
    real = ::Dexpace::Resilience::Policy
    # Merged BEFORE anything is defined: defining the conforming body and then overriding it warns
    # "method redefined", which NFR-6's fatal-warning hook turns into an error.
    bodies = { retry_eligible?: ->(status, set:) { real.retry_eligible?(status, set: set) },
               throwable_retryable?: ->(error) { real.throwable_retryable?(error) },
               cancellation?: ->(error) { real.cancellation?(error) }, }.merge(broken)
    policy = Module.new
    bodies.each { |name, body| policy.define_singleton_method(name, &body) }
    resilience_core(Policy: policy)
  end

  # The real Instrumentation with one `Redactor::DEFAULT` replaced. `Redactor` is a class carrying
  # a DEFAULT constant, so the double is built the same way rather than through `const_missing`.
  def instrumentation_with(redactor)
    Module.new do
      const_set(:Redactor, Class.new { const_set(:DEFAULT, redactor) })
      const_set(:Logger, Dexpace::Instrumentation::Logger)
      const_set(:Preview, Dexpace::Instrumentation::Preview)
      define_singleton_method(:contain) { |*a, **k, &b| Dexpace::Instrumentation.contain(*a, **k, &b) }
    end
  end

  # ---- XCUT-1 ----

  test "a cancellation classifier that reads only the outermost error fails XCUT-1" do
    outermost = policy_core(cancellation?: ->(error) { error.is_a?(::Dexpace::CancelledError) })

    assert_equal([:failed], statuses(Suite.run(core: outermost))["XCUT-1"],
                 "an adapter's own retryable wrapper around the token's raise is what makes a " \
                 "cancelled operation retryable again, and reading the outermost error misses it",)
  end

  test "a classifier that calls a cancellation retryable fails XCUT-1" do
    retrying = policy_core(throwable_retryable?: ->(_error) { true })

    assert_equal([:failed], statuses(Suite.run(core: retrying))["XCUT-1"])
  end

  # ---- XCUT-2 ----

  test "a cancellation matched by EXACT type fails XCUT-2's subtype clause" do
    exact = policy_core(cancellation?: lambda do |error|
      error.instance_of?(::Dexpace::CancelledError)
    end)

    assert_equal([:failed], statuses(Suite.run(core: exact))["XCUT-2"],
                 "a timeout type that SUBCLASSES the cancellation type must still be read as a " \
                 "cancellation, which is why the timeout branch has to be checked first",)
  end

  test "a classifier that refuses a read timeout fails XCUT-2" do
    by_message = policy_core(throwable_retryable?: lambda do |error|
      !error.message.include?("timed out")
    end)

    assert_equal([:failed], statuses(Suite.run(core: by_message))["XCUT-2"],
                 "telling a timeout from a cancellation by matching a message string is what " \
                 "XCUT-2 forbids in as many words",)
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

  # ---- XCUT-6 ----

  test "a capability query that reads only the outermost error fails XCUT-6" do
    outermost = policy_core(throwable_retryable?: lambda do |error|
      error.respond_to?(:retryable?) && error.retryable?
    end)

    assert_equal([:failed], statuses(Suite.run(core: outermost))["XCUT-6"],
                 "an adapter failure a higher layer wrapped still declares itself retryable " \
                 "through its cause chain, and never participates if only the outer is read",)
  end

  test "a classifier matching a concrete TYPE rather than the capability fails XCUT-6" do
    by_type = policy_core(throwable_retryable?: ->(error) { error.is_a?(::IOError) })

    assert_equal([:failed], statuses(Suite.run(core: by_type))["XCUT-6"],
                 "a custom error type the classifier has never heard of must participate " \
                 "WITHOUT the classifier being edited",)
  end

  # ---- XCUT-7 ----

  test "a configured set ANDed with the baked classifier fails XCUT-7's widening clause" do
    anded = policy_core(retry_eligible?: lambda do |status, set:|
      set.include?(status) && ::Dexpace::Retryability.retryable_status?(status)
    end)

    assert_equal([:failed], statuses(Suite.run(core: anded))["XCUT-7"],
                 "an AND passes the narrowing half and fails the widening one, which is why " \
                 "both directions are asserted",)
  end

  test "a default retryable-status set that is not the one XCUT-7 fixes fails XCUT-7" do
    settings = Module.new
    settings.define_singleton_method(:build) { Defaults.new([500, 502, 503, 504]) }

    assert_equal([:failed],
                 statuses(Suite.run(core: resilience_core(RetrySettings: settings)))["XCUT-7"],)
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

  # ---- XCUT-10 ----

  test "a safety gate that re-sends a body-less POST fails XCUT-10" do
    lenient = Module.new do
      def self.eligible?(request)
        body = request.body
        body.nil? || body.replayable?
      end
    end

    assert_equal([:failed], statuses(Suite.run(core: resilience_core(Resend: lenient)))["XCUT-10"],
                 "RETRY-7: a bare POST is not re-sendable even though there is no payload to " \
                 "re-send, and even when the failure never reached the server",)
  end

  test "a safety gate taking a FAILURE parameter fails XCUT-10's structural clause" do
    special_casing = Module.new do
      # rubocop:disable-next Lint/UnusedMethodArgument -- the parameter IS the defect here
      def self.eligible?(request, failure = nil)
        body = request.body
        return request.method.idempotent? if body.nil?

        body.replayable?
      end
    end
    core = resilience_core(Resend: special_casing)

    assert_equal([:failed], statuses(Suite.run(core: core))["XCUT-10"],
                 "every enumerated case is decided correctly here, so the only clause left to " \
                 "fail is the structural one: there must be nothing to special-case on",)
  end

  # ---- XCUT-19 ----

  test "a redactor that forwards a URL's userinfo fails XCUT-19" do
    leaky = Class.new do
      def url(value) = value
      def header_value(_name, value) = value
      def header_name?(_name) = false
    end
    report = Suite.run(core: patched(Instrumentation: instrumentation_with(leaky.new)))

    assert_equal([:failed], statuses(report)["XCUT-19"])
  end

  test "a header allow-list that is default-ALLOW fails XCUT-19" do
    permissive = Class.new do
      def url(value) = Dexpace::Instrumentation::Redactor::DEFAULT.url(value)
      def header_value(_name, value) = value
      def header_name?(_name) = true
    end
    report = Suite.run(core: patched(Instrumentation: instrumentation_with(permissive.new)))

    assert_equal([:failed], statuses(report)["XCUT-19"],
                 "the URL clauses pass against the real redactor, so the allow-list clause is " \
                 "the only one left to fail",)
  end

  # ---- XCUT-20 ----

  test "a redactor that throws on a malformed URL fails XCUT-20" do
    throwing = Class.new do
      def url(_value) = raise("boom")
      def header_value(_name, value) = value
      def header_name?(_name) = false
    end
    report = Suite.run(core: patched(Instrumentation: instrumentation_with(throwing.new)))

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
  # What a RetrySettings double's `.build` answers: XCUT-7 reads `#retryable_statuses` off it and
  # nothing else.
  Defaults = Struct.new(:retryable_statuses)

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

  # ---- XCUT-24 ----

  test "an error-body snapshot that multiplies its cap fails XCUT-24" do
    uncapped = Module.new do
      define_singleton_method(:buffer_bounded) do |body, cap:|
        ::Dexpace::Body.buffer_bounded(body, cap: cap * 1000)
      end
      define_singleton_method(:method_missing) do |name, *args, **kwargs, &block|
        ::Dexpace::Body.public_send(name, *args, **kwargs, &block)
      end
      define_singleton_method(:respond_to_missing?) { |name, _| ::Dexpace::Body.respond_to?(name) }
    end

    assert_equal([:failed], statuses(Suite.run(core: patched(Body: uncapped)))["XCUT-24"],
                 "the snapshot is the cap half; the logging tap is the non-consumption half, " \
                 "and a preview that capped but drained would pass this one alone",)
  end
end
