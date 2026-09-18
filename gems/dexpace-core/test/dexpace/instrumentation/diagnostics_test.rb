# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../support/fiber_storage_facts"
require_relative "../../support/warning_capture"
require_relative "../../support/diagnostic_context"
require_relative "../../../lib/dexpace/instrumentation/diagnostics"

# Exercises: OBS-10, OBS-23, OBS-24
#
# Phase 5c shipped this module's three constants early for phase 5b to adopt (P5-71) and pinned
# them here; phase 5b extends the file with .capture, .with and .folded and rewrites this mirror
# as its own -- 5c's "no method" pin is gone, its two constant cases and its Symbol-key case
# stay, and the "requires nothing" pin stays because 5c's independence_test.rb loads this file by
# name and must not acquire the logging half behind Tracing (R11). Every case that touches fiber
# storage runs inside DiagnosticContext.preserve (testing/4ef070df), and the two floor-sensitive
# assertions go through FiberStorageFacts.
#
# Split into nested classes under Metrics/ClassLength: the constants, the bridge, the fold.
class DexpaceInstrumentationDiagnosticsTest < DexpaceTestCase
  include FiberStorageFacts

  Diagnostics = Dexpace::Instrumentation::Diagnostics
  SOURCE = File.expand_path("../../../lib/dexpace/instrumentation/diagnostics.rb", __dir__)

  test "OBS-23: the two keys are the wire names as Symbols" do
    assert_equal(:"trace.id", Diagnostics::TRACE_ID)
    assert_equal(:"span.id", Diagnostics::SPAN_ID)
  end

  test "OBS-10: the default allow-list is exactly {trace.id, span.id}, frozen, in that order" do
    assert_equal(%i[trace.id span.id], Diagnostics::DEFAULT_KEYS)
    assert_predicate(Diagnostics::DEFAULT_KEYS, :frozen?)
    assert_same(Diagnostics::TRACE_ID, Diagnostics::DEFAULT_KEYS[0])
    assert_same(Diagnostics::SPAN_ID, Diagnostics::DEFAULT_KEYS[1])
  end

  # P5-39: the reserved prefix under which core's own fiber slots live (5c's current-span slot
  # among them), never folded in either mode; neither key 5b declares falls under it.
  test "P5-39: RESERVED_PREFIX is dexpace. and covers neither diagnostic key" do
    assert_equal("dexpace.", Diagnostics::RESERVED_PREFIX)
    refute(Diagnostics::TRACE_ID.name.start_with?(Diagnostics::RESERVED_PREFIX))
    refute(Diagnostics::SPAN_ID.name.start_with?(Diagnostics::RESERVED_PREFIX))
  end

  # R11: the file 5c's independence subprocess loads by name defines nothing of the logging half
  # and requires nothing, so Tracing can require it without acquiring Event, Keys or Logger.
  test "R11: the module holds four constants and three functions, and the file requires nothing" do
    assert_equal(%i[DEFAULT_KEYS RESERVED_PREFIX SPAN_ID TRACE_ID],
                 Diagnostics.constants(false).sort,)
    assert_equal(%i[capture folded with], Diagnostics.singleton_methods.sort)
    assert_empty(Diagnostics.instance_methods(false))
    refute_match(/^\s*require/, File.read(SOURCE), "diagnostics.rb must require nothing")
  end

  test "R11: a Symbol key is accepted by the per-key carrier API on this interpreter" do
    ::Fiber[Diagnostics::TRACE_ID] = "t"

    assert_equal("t", ::Fiber[Diagnostics::TRACE_ID])
    assert_equal(:"trace.id", ::Fiber.current.storage.keys.find { |k| k == :"trace.id" })
  ensure
    ::Fiber[Diagnostics::TRACE_ID] = nil
  end

  # OBS-24's snapshot and bridge.
  class BridgeTest < DexpaceTestCase
    include FiberStorageFacts

    Diagnostics = Dexpace::Instrumentation::Diagnostics

    # Asserted per key, not as whole-map equality: `rake test` shares one process and one main
    # fiber, so a whole-map assertion is one about every other suite's storage hygiene.
    test "OBS-24: capture is a frozen Hash of the present keys, a fresh object per call" do
      DiagnosticContext.preserve do
        ::Fiber[:"trace.id"] = "t1"
        snapshot = Diagnostics.capture

        assert_equal("t1", snapshot[:"trace.id"])
        assert_predicate(snapshot, :frozen?)
        refute_same(snapshot, Diagnostics.capture)
        refute_predicate(::Fiber.current.storage, :frozen?, "the live storage is untouched")
        assert(snapshot.keys.all?(::Symbol))
      end
    end

    # The floor decision: a nil-valued key is not a diagnostic-context value (OBS-10 skips it),
    # so it is absent from a snapshot on every row -- which makes the snapshot the same shape on
    # 3.2, where `= nil` leaves nil-valued keys behind, as on 3.3+, where only the warned setter
    # can create one. The input is built the only way it can be on 3.3+.
    test "OBS-24, OBS-10: capture omits a nil-valued key on every row" do
      DiagnosticContext.preserve do
        ::Fiber[:"dexpace.test.kept"] = "v"
        before = ::Fiber.current.storage
        WarningCapture.record { ::Fiber.current.storage = before.merge("dexpace.test.nil": nil) }

        assert(::Fiber.current.storage.key?(:"dexpace.test.nil"))
        snapshot = Diagnostics.capture

        refute(snapshot.key?(:"dexpace.test.nil"))
        assert_equal("v", snapshot[:"dexpace.test.kept"])
      ensure
        WarningCapture.record { ::Fiber.current.storage = before }
      end
    end

    test "OBS-24: capture reads {} inside a fiber that opted out of storage" do
      captured = ::Fiber.new(storage: nil) { Diagnostics.capture }.resume

      assert_equal({}, captured)
      assert_predicate(captured, :frozen?)
    end

    test "OBS-24: with installs the snapshot for the block and restores the prior context after" do
      DiagnosticContext.preserve do
        ::Fiber[:prior_key] = "prior"
        ::Fiber[:"trace.id"] = "before"
        snapshot = { "trace.id": "t2", introduced: "new" }.freeze

        value = Diagnostics.with(snapshot) do
          assert_equal("t2", ::Fiber[:"trace.id"])
          assert_equal("new", ::Fiber[:introduced])
          assert_equal("prior", ::Fiber[:prior_key], "keys the snapshot does not name are kept")
          :block_value
        end

        assert_equal(:block_value, value)
        assert_equal("before", ::Fiber[:"trace.id"], "an overwritten key is put back")
        assert_equal("prior", ::Fiber[:prior_key])
        assert_nil(::Fiber[:introduced])
        assert_diagnostic_key_removed(:introduced)
      end
    end

    test "OBS-24: with restores the prior context when the block raises" do
      DiagnosticContext.preserve do
        ::Fiber[:"trace.id"] = "before"
        snapshot = { "trace.id": "t2", introduced: "new" }

        error = assert_raises(::RuntimeError) do
          Diagnostics.with(snapshot) do
            assert_equal("t2", ::Fiber[:"trace.id"])
            raise "inside the bridge"
          end
        end

        assert_equal("inside the bridge", error.message)
        assert_equal("before", ::Fiber[:"trace.id"])
        assert_nil(::Fiber[:introduced])
        assert_diagnostic_key_removed(:introduced)
      end
    end

    # A new Thread INHERITS a copy of the parent's storage, so B's "original context" is not
    # empty; the assertion is that B's own prior comes back, never that it reads nil.
    test "OBS-24: with bridges a real thread boundary and restores B's own prior context" do
      DiagnosticContext.preserve do
        ::Fiber[:"trace.id"] = "parent_trace"
        snapshot = Diagnostics.capture.merge("span.id": "s1").freeze

        result = ::Thread.new do
          ::Fiber[:thread_local] = "orig"
          ::Fiber[:"trace.id"] = "b_own_trace"
          inside = nil
          Diagnostics.with(snapshot) { inside = [::Fiber[:"trace.id"], ::Fiber[:"span.id"]] }
          [inside, ::Fiber[:"trace.id"], ::Fiber[:thread_local], ::Fiber[:"span.id"]]
        end.value

        assert_equal(%w[parent_trace s1], result[0], "the captured keys are visible inside")
        assert_equal("b_own_trace", result[1], "B's own value is back")
        assert_equal("orig", result[2])
        assert_nil(result[3])
        assert_equal("parent_trace", ::Fiber[:"trace.id"], "mutations stay on the calling thread")
        assert_nil(::Fiber[:"span.id"])
      end
    end

    test "OBS-24: the snapshot is any object answering #each and #keys with Symbol keys" do
      DiagnosticContext.preserve do
        duck = ::Struct.new(:pairs) do
          def each(&) = pairs.each(&)
          def keys = pairs.keys
          def [](key) = pairs[key]
        end.new({ "trace.id": "duck" })

        Diagnostics.with(duck) { assert_equal("duck", ::Fiber[:"trace.id"]) }

        assert_nil(::Fiber[:"trace.id"])
      end
    end
  end

  # OBS-10's fold, in both modes.
  class FoldTest < DexpaceTestCase
    Diagnostics = Dexpace::Instrumentation::Diagnostics

    test "OBS-10: the allow-listed mode folds only present listed keys, keyed by Symbol#name" do
      DiagnosticContext.preserve do
        ::Fiber[:"trace.id"] = "1111"
        ::Fiber[:other_key] = "other"

        folded = Diagnostics.folded(Diagnostics::DEFAULT_KEYS)

        assert_equal({ "trace.id" => "1111" }, folded)
        assert_same(Diagnostics::TRACE_ID.name, folded.keys.first)
        refute_predicate(folded, :frozen?, "the fold is the event's to merge into")
      end
    end

    test "OBS-10: the allow-listed mode skips a nil-valued listed key" do
      DiagnosticContext.preserve do
        ::Fiber[:"span.id"] = "s"
        ::Fiber[:"span.id"] = nil

        assert_equal({}, Diagnostics.folded(Diagnostics::DEFAULT_KEYS))
      end
    end

    test "OBS-10: an empty allow-list folds nothing" do
      DiagnosticContext.preserve do
        ::Fiber[:"trace.id"] = "1111"

        assert_equal({}, Diagnostics.folded([]))
      end
    end

    # R12: the nil-valued key is the input OBS-10's "keys with null values MUST be skipped" is
    # about, and it is constructed the only way it can be on 3.3+ -- the warned whole-map
    # setter, inside WarningCapture so FatalWarnings does not fail the test. The ban is on lib/,
    # not on a test deliberately producing a host-made state.
    test "OBS-10: the unfiltered mode folds every present key and skips nil values" do
      DiagnosticContext.preserve do
        before = ::Fiber.current.storage
        warnings = WarningCapture.record do
          ::Fiber.current.storage = before.merge(a: nil, b: "beta")
        end

        assert_equal(1, warnings.size)
        folded = Diagnostics.folded(nil)

        assert_equal("beta", folded["b"])
        refute(folded.key?("a"))
        assert(folded.keys.all?(::String))
      ensure
        WarningCapture.record { ::Fiber.current.storage = before }
      end
    end

    # P5-39: the crossing neither design named. 5c stores the current span under
    # :"dexpace.current_span" and says it "must never be folded"; the unfiltered mode folds the
    # WHOLE map, so without the skip a live Span reaches OBS-6's rendering on every event. The
    # key is written literally: 5c's constant is a private_constant, which a qualified reference
    # cannot reach, and the literal is what the skip actually matches.
    test "OBS-10, P5-39: the unfiltered mode skips every dexpace.-prefixed slot" do
      DiagnosticContext.preserve do
        ::Fiber[:"dexpace.current_span"] = ::Object.new
        ::Fiber[Diagnostics::TRACE_ID] = "t1"
        ::Fiber[:tenant] = "acme"

        folded = Diagnostics.folded(nil)

        assert_equal("t1", folded["trace.id"])
        assert_equal("acme", folded["tenant"])
        refute(folded.keys.any? { |key| key.start_with?("dexpace.") })
      end
    end
  end
end
