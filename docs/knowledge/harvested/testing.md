# testing

## Rules
- Use Minitest with `test "..." do` blocks rather than `def test_name` methods, and require test helpers and subject files explicitly at the top of every test file.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:54-78` · high · sha:ee0ba4ee56f2</sub>
- Organize tests as `FooTest < Minitest::Test`, one test class per production class, in a `test/` directory mirroring `lib/`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:60-60` · high · sha:ee0ba4ee56f2</sub>
- Structure every test as arrange, act, assert (AAA) in blank-line-separated paragraphs, and test exactly one behaviour per test case.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:80-101` · high · sha:ee0ba4ee56f2</sub>
- Name test descriptions as "<verb-phrase> when <condition>" so the name itself communicates the failure mode.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:86-86` · high · sha:ee0ba4ee56f2</sub>
- Use descriptive assertions such as `assert_equal`, `assert_predicate`, and `refute_nil` rather than a bare `assert x == y`, because the descriptive form produces a targeted failure message.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:103-123` · high · sha:ee0ba4ee56f2</sub>
- Always pass `expected` before `actual` to `assert_equal`, since Minitest's diff output is backwards and misleading when the argument order is reversed.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:107-107` · high · sha:ee0ba4ee56f2</sub>
- Split a compound test that checks multiple unrelated properties of a result into separate, independent `test "..." do` blocks, one per aspect.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:125-151` · high · sha:ee0ba4ee56f2</sub>
- Never use `assert_nothing_raised`; instead assert the positive outcome directly, such as the return value or resulting state, when an operation is expected to succeed.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:153-171` · high · sha:ee0ba4ee56f2</sub>
- Prefer fakes (real in-memory implementations of an interface) over mocks for owned interfaces crossing a test boundary, since a mock couples the test to the call shape of production code while a fake exercises real behaviour and survives internal refactors.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:173-200` · high · sha:ee0ba4ee56f2</sub>
- Reserve true test doubles (stubs, `Minitest::Mock`) for genuine externals such as a third-party payment gateway, a system clock, or an SMS provider, never for code owned inside the module boundary.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:179-179` · high · sha:ee0ba4ee56f2</sub>
- Never name a hand-rolled test double `Mock*` when it is actually a fake; name doubles for what they are, using the `FakeX` naming convention.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:178-200` · high · sha:ee0ba4ee56f2</sub>
- Write property-based tests with bounded iteration counts for pure functions and value objects, covering canonical properties such as round-trip, idempotence, commutativity, and bounds.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:202-226` · high · sha:ee0ba4ee56f2</sub>
- Bound property-test generators explicitly, such as `rand(1..1_000_000)` rather than unbounded `rand`, and set a fixed iteration count so CI runtime is predictable.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:207-207` · high · sha:ee0ba4ee56f2</sub>
- Property-based round-trip tests are mandatory for codecs, parsers, serializers, and any value object with parse-constructor invariants.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:208-208` · high · sha:ee0ba4ee56f2</sub>
- Never read `Time.now` inside a unit under test; inject the clock as a parameter, or use a scoped `Time.stub :now, fixed_time do ... end` only when the caller cannot be refactored.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:228-248` · high · sha:ee0ba4ee56f2</sub>
- Pin any random seed used inside a property test and log it on failure so the counterexample sequence is reproducible.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:234-234` · high · sha:ee0ba4ee56f2</sub>
- Treat `srb tc` as the first test suite that runs on every push, before Minitest, and treat any type error it reports as a test failure that blocks merge.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:250-277` · high · sha:ee0ba4ee56f2</sub>
- Write `# typed: strict` on every test file, since test helpers are production-quality code carrying the same type discipline as `lib/`.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:256-256` · high · sha:ee0ba4ee56f2</sub>
- At every error boundary, pair a positive test with a negative one that asserts the expected `StandardError` subclass is raised, checks its message identifies the violating input, and verifies no partial side effect leaked.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:279-302` · high · sha:ee0ba4ee56f2</sub>
- Never rescue and ignore an exception in a test; always use the exception object returned by `assert_raises` to assert its class and message.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:285-285` · high · sha:ee0ba4ee56f2</sub>
- Pair-assert a property two independent ways (for example, assert the exact expected value and assert it is strictly less than an original value) so a bug surfaces at the assertion rather than downstream.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:284-284` · high · sha:ee0ba4ee56f2</sub>
- Every test must run alone, in any order, and pass; build every mutable fixture fresh per test (in the `test` block, `setup`, or a factory), and never override Minitest's randomized test-order seed to paper over order dependence.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:304-334` · high · sha:ee0ba4ee56f2</sub>
- Bound property-test data sizes and iteration counts, keeping generators capped (for example `rand(1..100)` not `rand`) and the whole suite well under 30 seconds.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:310-310` · high · sha:ee0ba4ee56f2</sub>
- A conformance checklist item the port has decided not to satisfy is reported as a failure by the conformance suite and suppressed in the port's own build through a named waiver listing the requirement ID, so the gap stays visible rather than disappearing into a restated item. (NFR-8, NFR-9)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:109-112` · high · sha:b9270d5d1ef8</sub>

## Constraints

## Conclusions
- Minitest was chosen over RSpec as the test framework even though RSpec is more widely used in the Ruby application world, has a richer matcher library, better failure output on complex expectations, and shared-example groups that would express the conformance suite's per-adapter parametrisation more naturally; Minitest wins because it ships with the interpreter as a default gem, so a first-party suite runs with nothing installed and does not impose a third-party assertion DSL on adapter authors.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:67-74` · high · sha:b9270d5d1ef8</sub>
- dexpace-conformance's assertions are plain assertion objects — each a callable that either returns cleanly or raises a Dexpace::Conformance::Failure carrying expected and actual values — with thin Minitest and RSpec drivers over them, so Minitest appears only as a development dependency of the first-party build and never as a runtime constraint on a consumer, and an adapter author on RSpec runs the same assertions.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:74-79` · high · sha:b9270d5d1ef8</sub>
- Transport conformance tests run against a local TCPServer-based fixture rather than a stubbing library for two reasons: transport requirements involve socket-level behaviour a stub cannot express (connect-versus-read timeout classification, lazily-read streaming bodies whose close cascades to connection release, chunked framing, a half-closed peer, malformed inbound headers dropped individually, vendor status codes surfaced faithfully), and a stubbing library needs a per-client shim so the same assertions could not run unchanged against other adapters like dexpace-transport-async_http or a future httpx adapter. (TRANSPORT-3, TRANSPORT-4, TRANSPORT-25, TRANSPORT-14, TRANSPORT-24)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:81-89` · high · sha:b9270d5d1ef8</sub>

## Reference
- Minitest is the single test framework for every dexpace Ruby project; no second test runner is introduced.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:57-57` · high · sha:ee0ba4ee56f2</sub>
- `assert_nothing_raised` was removed from Minitest 6+ because it inverts the test model, checking absence of explosion rather than presence of correctness.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:109-109` · high · sha:ee0ba4ee56f2</sub>
- Immutable shared test data, such as a frozen constant or a fixed value object, is safe to hoist to class level and share across tests, unlike mutable fixtures.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/11-testing.md:309-309` · high · sha:ee0ba4ee56f2</sub>
- Chapter 11 (Testing) covers Minitest, `test "..."` blocks, AAA paragraphs, descriptive assertions, fakes over mocks, property tests, determinism via injected `Time`, and `srb tc` as the first test suite.
  <sub>styleguide · `/home/mohammad/Projects/dexpace/styleguide/ruby/README.md:44-44` · high · sha:fa61163448dd</sub>
- For pipeline, model, parser, and policy tests, plain Minitest with hand-built fakes suffices, with a stubbing library intercepting at the Net::HTTP level where a test needs a canned response without a socket.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:79-81` · high · sha:b9270d5d1ef8</sub>
- The transport conformance suite also carries lifecycle assertions that close is idempotent, a caller-supplied client survives close, and a post-close send raises, because these are clauses an adapter author is most likely to satisfy by accident on the first call and not on the second. (SEAM-14, XCUT-22, SEAM-15)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:90-92` · high · sha:b9270d5d1ef8</sub>
- The specification's Appendix B conformance checklist covers only the PAGE, SSE, SERDE, OBS, CFG, TRANSPORT, ASYNC, XCUT, and NFR sections; it has no sections for SEAM, HTTP, IO, BODY, CTX, PIPE, RECOV, RETRY, REDIR, or AUTH, so a port claiming Appendix B conformance claims considerably less than full conformance, and this port states that explicitly.
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:94-97` · high · sha:b9270d5d1ef8</sub>
- Appendix B checklist items are restated in three places: B.3's reified-helper item becomes "the ergonomic decode helper routes through a witness or combinator," B.5's four-layer precedence item names the configure tier as layer three, and B.8's seam-resolution item names require-time registration as the discovery substrate. (SERDE-7)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:97-100` · high · sha:b9270d5d1ef8</sub>
- B.4 is exercised as written except for allocation-freeness items, which are restated as allocation-count assertions on the disabled path, while the shared-inert-event identity assertion is kept exactly as written because the log event object now exists to assert it against. (OBS-1)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:100-102` · high · sha:b9270d5d1ef8</sub>
- B.6 is exercised per adapter, with two transport requirement items vacuous for Net::HTTP and mandatory for any adapter whose client has those code paths. (OBS-1, TRANSPORT-8, TRANSPORT-18)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:102-104` · high · sha:b9270d5d1ef8</sub>
- B.7 needs the most restating because its items presume pooled-thread interrupt delivery and an executor lifecycle: one async requirement is vacuous by construction and another's item is recorded as failing rather than vacuous, since dexpace-async-thread supplies the blocking-task-on-a-worker antecedent the requirement conditions on. (ASYNC-4, ASYNC-3, ASYNC-1, ASYNC-8, ASYNC-12, ASYNC-15, ASYNC-17)
  <sub>design · `docs/sdk-design-ruby/09-toolchain-and-quality-gates.md:104-108` · high · sha:b9270d5d1ef8</sub>

## Conflicts

## Superseded
