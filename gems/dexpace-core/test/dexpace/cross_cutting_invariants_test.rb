# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# XCUT-1, XCUT-2, XCUT-3, XCUT-5, XCUT-6, XCUT-7, XCUT-8, XCUT-9, XCUT-10, XCUT-11, XCUT-12,
# XCUT-13, XCUT-14, XCUT-15, XCUT-16, XCUT-17, XCUT-18, XCUT-19, XCUT-20, XCUT-21, XCUT-22,
# XCUT-23, XCUT-24. The first-party driver for dexpace-conformance's InvariantSuite (phase 9's
# design R6 and its plan Tasks 5-8): the suite is written against the loaded core module and a
# handful of factories it cannot build itself, and THIS file supplies them.
#
# Placement. The suite lives in dexpace-conformance and the subjects are core's, so the driver is
# in core's own test tree -- 8a's precedent, where the transport suite's driver lives in
# dexpace-transport-net_http/test/. Core's gemspec is untouched: dexpace-conformance is a path gem
# in the workspace Gemfile and this is a test-time require, exactly as 8a's driver requires it.
#
# One generated test per assertion, each building a FRESH InvariantCase (the Runner's own
# discipline: a fixture shared across a run is what made this phase's planning double pass
# spuriously), so a `-n` filter runs the same code a full run does. A Vacuous is a skip naming the
# reason, a Failure a flunk naming the ids; anything else propagates as an error and is never
# silently a failure. Beside them, ONE report-level test, because a per-assertion skip is not a
# disposition: the report is where a MUST-level vacuity becomes a blocker (plan Task 12a).
#
# MinitestDriver is deliberately not used: 8a wrote it around TransportCase and phase 9 reports
# rather than refactors phase 8's files (design R6). The residue is real -- two driver loops in
# one repository -- and is stated here rather than hidden.
require_relative "../test_helper"
require_relative "../support/auth_fixtures"
require_relative "../support/challenge_fixtures"
require_relative "../support/redirect_fixtures"
require_relative "../support/scripted_transport"
require "dexpace/conformance"

# rubocop:disable Metrics/ClassLength -- one driver for twenty-eight assertions plus the
# factories none of them can build. Splitting it would put half the factories in a second
# file that has to be read with this one to mean anything, which is .rubocop.yml's own
# recorded argument against counting rather than reading.
class DexpaceCrossCuttingInvariantsTest < DexpaceTestCase
  include AuthFixtures
  include RedirectFixtures

  Conformance = Dexpace::Conformance
  SUITE = Conformance::InvariantSuite

  # XCUT-18's second assertion drives a real adapter's dispatch path, and core ships no adapter:
  # its `transport:` factory is 8a's, supplied by the aggregate run (phase 9 plan, Task 16 Step 2),
  # and each first-party adapter carries its own wire-boundary test besides. Vacuous HERE and real
  # THERE -- which is why it is accepted with a citation rather than waived, and why the MODEL-layer
  # XCUT-18 assertion in the same group runs for real in this file.
  ACCEPTED_VACUOUS = {
    "XCUT-18" => "the call-site re-validation is an adapter property: the aggregate run supplies " \
                 "transport: (phase 9 plan, Task 16 Step 2) and phase 8's adapters each carry " \
                 "their own wire-boundary test. The model-layer XCUT-18 assertion runs here.",
  }.freeze

  # The key the shared stamper writes, and the header the cross-talk observation reads back.
  CREDENTIAL_HEADER = "Authorization"
  LABEL_HEADER = "X-Conformance-Label"
  # One shared, frozen KeyStamper, reached by every thread and both fibers. A CONSTANT rather than
  # an ivar of the seam, so the seam's own ivars are exactly the latch, the lock, the count it
  # guards and the borrowed resource -- and `mutable:` below stays a statement about lifecycle
  # state and not a list of everything the object happens to hold.
  STAMPER = Dexpace::Auth::KeyStamper.new(Dexpace::Auth::KeyCredential.new(api_key: "conformance"))

  # The closeable, callable SDK component XCUT-11, XCUT-13 and XCUT-22 are all assertions about.
  #
  # Assembled from core's own primitives and nothing else: the latch, the ownership rule and the
  # once-only release are Dexpace::Closeable's, and the per-call work runs through the shared
  # frozen KeyStamper. `owned:` is the whole of XCUT-22 -- a caller-supplied client makes this a
  # BORROWING wrapper, so core's #close flips the latch and returns without running #release, which
  # is the only thing standing between the SDK and closing a resource it did not create.
  class Seam
    include Dexpace::Closeable

    # @return [Integer] how many times #release actually ran -- the resource-side count XCUT-13's
    #   idempotency is measured with, never inferred from #close's return value
    attr_reader :release_count

    def initialize(client: nil)
      @client = client
      @lock = ::Thread::Mutex.new
      @release_count = 0
      initialize_closeable(owned: client.nil?)
    end

    # No lock is taken here, deliberately: XCUT-11's second clause drives two fibers of ONE thread
    # through this method on either side of a Fiber.yield, and Ruby's Mutex is per-fiber and
    # non-reentrant, so a lock held across that yield deadlocks. The work is a fresh request per
    # call through a frozen shared stamper, so there is nothing to guard.
    #
    # @param label [String] this call's identity, carried into the request and read back out
    # @return [Array(String, String)] the label as the stamped request carries it, and the key
    def call(label)
      builder = Dexpace::Headers.builder
      builder.add(LABEL_HEADER, label)
      request = Dexpace::Request.build(method: "GET", url: "https://a.example/x",
                                       headers: builder.build,)
      stamped = STAMPER.call(request)
      [stamped.headers[LABEL_HEADER].first, stamped.headers[CREDENTIAL_HEADER].first]
    end

    private

    # Genuinely closes what it holds, so `owned: false` and not an omission is what spares a
    # borrowed client. A seam that never touched its client would pass XCUT-22 by accident.
    def release
      @lock.synchronize { @release_count += 1 }
      @client&.close
      nil
    end
  end

  # Every ivar Seam holds, which is what design R8's predicate measures an unfrozen shared instance
  # against: Closeable's three (`@dexpace_owned`, `@dexpace_closed` and the latch mutex it is
  # written under), the lock, the count that lock guards, and the borrowed client. Nothing here is
  # per-call state, which is the thing XCUT-11 forbids and this declaration makes visible.
  SEAM_MUTABLE = %i[
    @dexpace_owned @dexpace_closed @dexpace_close_mutex @lock @release_count @client
  ].freeze

  SUITE.assertions.each_with_index do |assertion, index|
    define_method(format("test_%<n>02d_%<name>s", n: index,
                                                  name: assertion.name.gsub(/\W+/, "_"),)) do
      drive(assertion)
    end
  end

  test "the suite reports no failure, no error and no unaccepted MUST-level vacuity" do
    report = SUITE.run(**suite_arguments)

    assert_empty(report.failures.map { |result| described(result) })
    assert_empty(report.errors.map { |result| described(result) })
    assert_empty(report.blocking_vacuities.map { |result| result.assertion.ids.join(", ") },
                 "a MUST-level vacuity is a report blocker until it is accepted with a citation",)
    assert_predicate(report, :passed?)
  end

  # The accepted vacuity is a claim about THIS driver, so it is asserted rather than described: if
  # core ever gains a transport factory here, the acceptance is dead weight and this goes red.
  test "the one accepted vacuity is the call-site assertion, and it is really vacuous here" do
    report = SUITE.run(**suite_arguments)

    assert_equal(1, report.accepted_vacuities.size)
    assert_equal(["XCUT-18"], report.accepted_vacuities.first.assertion.ids)
    assert_equal(1, report.vacuous.size, "a second vacuity appeared with no citation behind it")
  end

  # Design R8's list, audited through the same predicate the suite applies to the seam. Frozen
  # instances pass on `frozen?` alone; the two unfrozen ones declare what they hold, and a subject
  # that grew a per-call ivar since this list was written goes red here.
  test "every shared instance core publishes holds only declared lifecycle state" do
    shared_instances.each do |(label, object, declared)|
      Conformance::SharedInstance.audit(object, mutable: declared)
    rescue Conformance::Failure => error
      flunk("#{label}: #{error.message} (declared #{error.expected.inspect}, holds " \
            "#{error.actual.inspect})")
    end
  end

  private

  def described(result) = "#{result.assertion.ids.join(", ")}: #{result.detail}"

  def drive(assertion)
    assertion.call(invariant_case)
  rescue Conformance::Vacuous => error
    skip("vacuous: #{error.reason}")
  rescue Conformance::Failure => error
    flunk("#{assertion.ids.join(", ")}: #{error.message} (expected #{error.expected.inspect}, " \
          "got #{error.actual.inspect})")
  end

  def invariant_case = Conformance::InvariantCase.new(**suite_arguments.except(:accepted_vacuous))

  def suite_arguments
    { core: ::Dexpace, seam: ->(client: nil) { Seam.new(client: client) },
      mutable: SEAM_MUTABLE, shared: shared_instances, bounded_map: bounded_map_factory,
      bounded_map_store: bounded_map_store_reader, cnonce: cnonce_driver,
      redirect_hops: redirect_driver, credential_hop: credential_driver,
      accepted_vacuous: ACCEPTED_VACUOUS, }
  end

  # Dexpace::BoundedMap is a private_constant of Dexpace, reachable by its BARE name from a
  # full-nesting body and by Dexpace.const_get, but not by the scoped spelling (4a's P4-3) -- which
  # is exactly why the suite takes a factory instead of naming it.
  def bounded_map_factory = ->(cap:) { ::Dexpace.const_get(:BoundedMap).new(cap: cap) }

  # XCUT-14's drain clause needs the backing Hash, which BoundedMap keeps private; the driver knows
  # the name, so the suite never reaches into the object.
  def bounded_map_store_reader = ->(map) { map.instance_variable_get(:@h) }

  # 6c's DigestHandler draws its cnonce inside #authorization_for, so the rendered header value is
  # the only place the drawn bytes are observable.
  def cnonce_driver
    lambda do |source|
      handler = Dexpace::Auth::DigestHandler.new(
        Dexpace::Auth::PasswordCredential.build(username: "u", password: "p"),
        cnonce_source: source,
      )
      handler.authorization_for(Dexpace::Auth::Challenges.parse(ChallengeFixtures::DIGEST_MD5),
                                https_request,)
    end
  end

  # One hop through 6b's real step over a scripted 3xx, answering the RE-ISSUED request. The
  # downgrade case never reaches the second script entry: the step raises before it re-issues,
  # which is the refusal XCUT-17 clause (d) is about.
  def redirect_driver
    lambda do |from:, to:, headers:|
      transport = ScriptedTransport.new([response_with(302, location: to), response_with(200)])
      # The suite hands each name its FULL value list, because XCUT-17 is about a header that may
      # legitimately repeat; RedirectFixtures#seed_request adds one value per call.
      seed = seed_request(from, headers: headers.flat_map { |n, vs| Array(vs).map { [n, _1] } })
      redirect_pipeline(redirect_step, transport).call(seed)
      sent_requests(transport).last
    end
  end

  # One drive of 6c's real step, with 6b's cross-origin marker forked into the REDIRECT slot the
  # step reads. The HTTPS guard raises out of the pipeline, which is the loud refusal XCUT-16 names.
  def credential_driver
    lambda do |url:, cross_origin: false|
      step = Dexpace::Auth::Step.build(stamper: STAMPER)
      transport = ScriptedTransport.new([closable_response(200)])
      pipeline = auth_pipeline(step, transport, redirect_state: { cross_origin: cross_origin })
      pipeline.call(Dexpace::Request.build(method: "GET", url: url,
                                           headers: Dexpace::Headers::EMPTY,))
      transport.calls.last.first
    end
  end

  # Design R8's nine subjects and the rest core publishes, as [label, object, declared ivars].
  # A frozen instance declares nothing: it conforms on `frozen?` alone, whatever it holds.
  def shared_instances
    instrumentation_singletons + [
      ["Dexpace::ContextStore.default", Dexpace::ContextStore.default, [:@map]],
      ["Dexpace::Clock::SYSTEM", Dexpace::Clock::SYSTEM, []],
      ["Dexpace::Configuration::EMPTY", Dexpace::Configuration::EMPTY, []],
      ["Dexpace::Resilience::RetrySettings", Dexpace::Resilience::RetrySettings.build, []],
      ["Dexpace::Resilience::RetryStep", Dexpace::Resilience::RetryStep.build, []],
      ["Dexpace::Resilience::AsyncRetryStep", Dexpace::Resilience::AsyncRetryStep.build, []],
      ["Dexpace::Redirect::Step", Dexpace::Redirect::Step.build, []],
      ["Dexpace::Auth::KeyStamper", STAMPER, []],
      ["Dexpace::Auth::Step", Dexpace::Auth::Step.build(stamper: STAMPER), []],
      # The one unfrozen pillar: the pipeline both runtimes share. Closeable's three, the frozen
      # entry and step lists it resolved once, the transport it dispatches to and the driver class
      # it instantiates per call -- Cursor is 4c's deliberate per-call state and lives on the stack,
      # never here.
      ["Dexpace::Pipeline.standard", Dexpace::Pipeline.standard(ScriptedTransport.new([])),
       %i[@dexpace_owned @dexpace_closed @dexpace_close_mutex @entries @steps @transport
          @driver_class],],
    ]
  end

  # 5c's no-op singletons and 5b's redaction pair: every one frozen, which is R8's first half.
  def instrumentation_singletons
    instrumentation = Dexpace::Instrumentation
    { "NO_SPAN" => instrumentation::NO_SPAN, "NO_TRACER" => instrumentation::NO_TRACER,
      "NO_TRACER_FACTORY" => instrumentation::NO_TRACER_FACTORY,
      "NO_SCOPE" => instrumentation::NO_SCOPE, "NO_METER" => instrumentation::NO_METER,
      "NULL_SINK" => instrumentation::NULL_SINK, "NULL (http tracer)" => instrumentation::NULL,
      "Logger::NULL" => instrumentation::Logger::NULL,
      "Redactor::DEFAULT" => instrumentation::Redactor::DEFAULT,
      "RedactionPolicy::DEFAULT" => instrumentation::RedactionPolicy::DEFAULT, }
      .map { |name, object| ["Dexpace::Instrumentation::#{name}", object, []] }
  end
end
# rubocop:enable Metrics/ClassLength
