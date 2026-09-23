# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace/conformance"

# Appendix B.8's instrument, proven against DELIBERATELY NON-CONFORMING doubles: a green suite
# proves the instrument works, not that the SDK conforms, and those are different claims.
# XCUT-11, XCUT-13, XCUT-14, XCUT-15, XCUT-17, XCUT-18, XCUT-21, XCUT-22.
class DexpaceConformanceInvariantSuiteTest < DexpaceTestCase # rubocop:disable Metrics/ClassLength -- the non-conforming doubles this suite must fail against live beside the tests that drive them, which is what keeps each test readable as one behaviour
  Suite = Dexpace::Conformance::InvariantSuite

  # ---- the seam: a latched closeable that counts its release ----

  # A conforming seam: a latched closeable that counts its release and holds no per-call state.
  class LatchedSeam
    attr_reader :release_count

    def initialize(client: nil)
      @client = client
      @owned = client.nil?
      @closed = false
      @release_count = 0
      @lock = Thread::Mutex.new
    end

    def call(request) = [request, 1]

    def close
      @lock.synchronize do
        return nil if @closed

        @closed = true
      end
      @release_count += 1
      @client.close if @owned && !@client.nil?
      nil
    end
  end

  # XCUT-13's first clause, broken: no latch, so every close runs the release again.
  class UnlatchedSeam < LatchedSeam
    def close
      @release_count += 1
      @client&.close
      nil
    end
  end

  # Blocks on its FIRST close only, just past the assertion's half-second bound: enough to make
  # XCUT-13's second clause red without spending seconds of the suite's time.
  class BlockingCloseSeam < LatchedSeam
    BLOCK_SECONDS = 0.6

    def close
      super
      Kernel.sleep(BLOCK_SECONDS) if release_count == 1
      nil
    end
  end

  # XCUT-22, broken: it closes the resource it borrowed.
  class OverreachingSeam < LatchedSeam
    def close
      super
      @client&.close
    end
  end

  # XCUT-11, broken: per-call state on the shared instance, and one call's request in another's.
  class CrossTalkingSeam < LatchedSeam
    def initialize(client: nil)
      super
      @attempt = 0
    end

    def call(_request) = ["request-0", @attempt += 1]
  end

  # Holds its per-fiber mutex across a suspension point, which is exactly what XCUT-11's second
  # clause forbids. Clause 1 drives the same object from a thread's ROOT fiber, where Fiber.yield
  # raises FiberError -- the rescue is the DOUBLE's, never the assertion's.
  class SuspendingLockSeam < LatchedSeam
    def call(request)
      @lock.synchronize do
        begin
          Fiber.yield
        rescue FiberError
          nil
        end
        [request, 1]
      end
    end
  end

  # A shared instance whose #call never returns. XCUT-11's first clause spawns sixteen callers, so
  # without a bound on the joins the assertion parks the whole run against it (R0-1). Not a
  # subclass of LatchedSeam: a seam that blocks on EVERY call blocks assertions this one does not
  # own, so the test drives the single assertion and the double needs nothing else.
  class BlockingCallSeam
    attr_reader :release_count

    def initialize(entered:, gate:, client: nil)
      @entered = entered
      @gate = gate
      @client = client
      @release_count = 0
    end

    def call(request)
      @entered << Thread.current
      [request, @gate.pop]
    end

    def close
      @release_count += 1
      nil
    end
  end

  BLOCKING_DECLARED = %i[@entered @gate @client @release_count].freeze

  DECLARED = %i[@client @owned @closed @release_count @lock].freeze

  # ---- bounded maps ----

  # 4a's filed BoundedMap surface: .new(cap:), #set, #size, and a drain loop over the store.
  class ConformingMap
    def initialize(cap:)
      @cap = cap
      @h = {}
      @mutex = Thread::Mutex.new
    end

    def set(key, value)
      @mutex.synchronize do
        @h[key] = value
        @h.shift while @h.size > @cap
      end
      value
    end

    def size = @mutex.synchronize { @h.size }
  end

  # XCUT-14's cap clause, broken: nothing evicts.
  class UncappedMap < ConformingMap
    def set(key, value)
      @mutex.synchronize { @h[key] = value }
      value
    end
  end

  # Caps correctly from empty, and is exactly XCUT-14's "single pre-insert check-then-evict".
  class CheckThenEvictMap < ConformingMap
    def set(key, value)
      @mutex.synchronize do
        @h.shift if @h.size >= @cap
        @h[key] = value
      end
      value
    end
  end

  STORE = ->(map) { map.instance_variable_get(:@h) }

  # ---- redirect hops ----

  Hop = Struct.new(:headers, :url)
  ORIGIN = %r{\Ahttps?://[^/]+}
  USERINFO = %r{//[^@/]*@}

  SCOPED_HEADERS = %w[authorization cookie proxy-authorization].freeze

  def conforming_hop(from:, to:, headers:)
    raise ArgumentError, "downgrade refused" if from.start_with?("https:") && to.start_with?("http:")

    target = to.sub(USERINFO, "//")
    dropped = from[ORIGIN] == target[ORIGIN] ? %w[authorization] : SCOPED_HEADERS
    Hop.new(headers.except(*dropped), target)
  end

  # A non-conforming re-issue: every header survives every hop.
  # rubocop:disable-next Lint/UnusedMethodArgument -- the driver contract's signature
  def leaky_hop(from:, to:, headers:) = Hop.new(headers, to)

  # ---- helpers ----

  def statuses(report)
    report.results.each_with_object({}) { |r, h| (h[r.assertion.ids.first] ||= []) << r.status }
  end

  def run_suite(**over)
    defaults = { core: ::Dexpace, seam: ->(client: nil) { LatchedSeam.new(client: client) },
                 mutable: DECLARED, }
    Suite.run(**defaults, **over)
  end

  # ---- structure ----

  test "the suite covers all 24 XCUT ids with 28 assertions, four of them doubled" do
    ids = Suite.assertions.flat_map(&:ids)

    assert_equal(24, ids.uniq.size)
    assert_equal(28, ids.size)
    assert_equal(%w[XCUT-11 XCUT-13 XCUT-14 XCUT-18], ids.tally.select { |_, n| n > 1 }.keys.sort)
    assert(ids.all? { |id| Dexpace::Conformance::Levels.known?(id) },
           "every id the suite declares is one appendix C holds",)
  end

  test "an absent artifact is vacuous naming who promised it, never failed and never errored" do
    report = Suite.run(core: Module.new, seam: ->(client: nil) { LatchedSeam.new(client: client) })

    assert_equal([:vacuous], statuses(report)["XCUT-15"])
    assert_includes(report.to_s, "Headers is absent; phase 1's domain model committed to it")
  end

  test "a factory the driver did not supply is vacuous, and on a MUST it blocks the report" do
    report = Suite.run(core: ::Dexpace)

    assert_equal(%i[vacuous vacuous], statuses(report)["XCUT-13"])
    refute_predicate(report, :passed?, "an un-waived MUST-level vacuity is a report blocker")
    assert_includes(report.to_s, "no seam implementation supplied")
  end

  # ---- the model and lifecycle assertions ----

  test "a model aliasing a caller's collection fails XCUT-15" do
    aliasing = Module.new do
      const_set(:Headers, Class.new do
        def self.build(values:, casing:, direction: :outbound) = new(values, casing, direction)
        def initialize(values, _casing, _direction) = (@values = values)
        def [](name) = @values[name]
      end,)
    end

    assert_equal([:failed], statuses(Suite.run(core: aliasing))["XCUT-15"])
  end

  test "an unlatched close fails XCUT-13's first clause and passes its second" do
    report = run_suite(seam: ->(client: nil) { UnlatchedSeam.new(client: client) })

    assert_equal(%i[failed passed], statuses(report)["XCUT-13"])
  end

  # XCUT-13's second clause is not vacuous: a close that blocks makes it red, which is what the
  # bound is for. Without a double that blocks, the clause would pass against every subject the
  # suite can build and would be worth nothing.
  test "a close that blocks fails XCUT-13's second clause and passes its first" do
    report = run_suite(seam: ->(client: nil) { BlockingCloseSeam.new(client: client) })

    assert_equal(%i[passed failed], statuses(report)["XCUT-13"])
    assert_match(/blocked rather than signalling/, report.failures.first.detail)
  end

  test "a holder that closes a borrowed resource fails XCUT-22" do
    report = run_suite(seam: ->(client: nil) { OverreachingSeam.new(client: client) })

    assert_equal([:failed], statuses(report)["XCUT-22"])
  end

  # ---- bounded memory ----

  test "a map with no cap fails XCUT-14's cap clause deterministically, with no thread race" do
    report = run_suite(bounded_map: lambda { |cap:|
      UncappedMap.new(cap: cap)
    }, bounded_map_store: STORE,)

    assert_equal(:failed, statuses(report)["XCUT-14"].first)
  end

  test "a drain-loop map passes both of XCUT-14's clauses" do
    report = run_suite(bounded_map: ->(cap:) { ConformingMap.new(cap: cap) },
                       bounded_map_store: STORE,)

    assert_equal(%i[passed passed], statuses(report)["XCUT-14"])
  end

  test "a check-then-evict map passes the cap clause and fails the drain clause" do
    report = run_suite(bounded_map: ->(cap:) { CheckThenEvictMap.new(cap: cap) },
                       bounded_map_store: STORE,)

    assert_equal(%i[passed failed], statuses(report)["XCUT-14"])
    assert_match(/evicted once instead of draining/, report.failures.first.detail)
  end

  # ---- redirect hygiene ----

  test "a redirect driver that keeps Authorization on a same-origin re-issue fails XCUT-17" do
    report = run_suite(redirect_hops: method(:leaky_hop))

    assert_equal([:failed], statuses(report)["XCUT-17"])
  end

  test "a conforming redirect driver passes all four of XCUT-17's clauses" do
    report = run_suite(redirect_hops: method(:conforming_hop))

    assert_equal([:passed], statuses(report)["XCUT-17"])
  end

  # ---- concurrency ----

  test "a frozen stateless seam passes both XCUT-11 clauses" do
    frozen = Class.new(LatchedSeam) do
      def initialize(client: nil)
        super
        freeze
      end
    end
    report = run_suite(seam: ->(client: nil) { frozen.new(client: client) }, mutable: [])

    assert_equal(%i[passed passed], statuses(report)["XCUT-11"])
  end

  test "a latch-and-mutex seam passes XCUT-11 when the DRIVER declares its state" do
    report = run_suite

    assert_equal(%i[passed passed], statuses(report)["XCUT-11"],
                 "P9-9: a frozen-and-no-ivars rule would condemn every Closeable in the SDK",)
  end

  test "a seam holding per-call state on the shared instance fails XCUT-11" do
    report = run_suite(seam: ->(client: nil) { CrossTalkingSeam.new(client: client) })

    assert_includes(statuses(report)["XCUT-11"], :failed)
  end

  test "a subject declaring per-call state exempt still fails; mutable: is the driver's" do
    self_exempting = Class.new(CrossTalkingSeam) do
      def conformance_mutable_state = [:@attempt]
    end
    report = run_suite(seam: ->(client: nil) { self_exempting.new(client: client) },
                       mutable: DECLARED,)

    assert_includes(statuses(report)["XCUT-11"], :failed)
  end

  # The deadlock must be reported :failed; :error reads as a broken harness. Asserted as the exact
  # PAIR, sorted, because assert_includes(:failed) would not catch the :error either.
  test "a seam holding its lock across a suspension point fails XCUT-11's second clause" do
    report = run_suite(seam: ->(client: nil) { SuspendingLockSeam.new(client: client) })

    assert_equal(%i[failed passed], statuses(report)["XCUT-11"].sort,
                 "a deadlock must be reported :failed; :error reads as a broken harness",)
  end

  # R0-1: the sixteen callers were joined with no bound, so a shared instance that never returns
  # parked the run instead of failing the clause. 8a's rule for this gem is the opposite -- every
  # wait carries a bound, so a non-conforming subject fails the assertion.
  test "a shared instance whose call never returns fails XCUT-11 rather than hanging the run" do
    entered = Thread::Queue.new
    gate = Thread::Queue.new
    assertion = Suite.assertions.find { |one| one.name.include?("holds no per-call state") }
    subject = Dexpace::Conformance::InvariantCase.new(
      core: ::Dexpace, mutable: BLOCKING_DECLARED,
      seam: lambda { |client: nil|
        BlockingCallSeam.new(entered: entered, gate: gate, client: client)
      },
    )

    error = assert_raises(Dexpace::Conformance::Failure) { assertion.call(subject) }

    assert_match(/did not return on every thread/, error.message)
  ensure
    release(entered, gate)
  end

  # Releases every caller parked on `gate` and joins each one, so a test driving a blocking double
  # leaves the thread count where it found it (DexpaceTestCase's teardown).
  def release(entered, gate)
    gate.close
    callers = []
    loop do
      one = entered.pop(timeout: 0.5)
      break if one.nil?

      callers << one
    end
    callers.each { |thread| thread.join(2) }
  end

  test "a shared instance the driver declares is audited too, and names itself on failure" do
    leaky = Class.new { def initialize = (@per_call = 0) }.new
    report = run_suite(shared: [["4a's ContextStore", leaky, []]])

    assert_includes(statuses(report)["XCUT-11"], :failed)
    assert_match(/4a's ContextStore/, report.failures.first.detail)
  end
end
