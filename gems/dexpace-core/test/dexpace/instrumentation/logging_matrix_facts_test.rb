# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "uri"
require_relative "../../test_helper"
require_relative "../../support/fiber_storage_facts"
require_relative "../../support/warning_capture"
require_relative "../../support/diagnostic_context"
require_relative "../../support/recording_sink"

# Exercises: OBS-1, OBS-2, OBS-7, OBS-10, OBS-12, OBS-15, OBS-24, OBS-38
#
# The floor-straddling facts the logging half rests on (the design's facts 1, 2, 3, 6, 7, 9, 10
# and 11), re-run on every interpreter in the matrix as a standing test rather than trusted from
# the 3.4.10 machine the design was written on. Two of them do NOT hold on the 3.2 floor -- the
# `Fiber[:k] = nil` deletion and, following from it, the exactness of the union restore -- and
# the assertions below pin what each row does instead of one interpreter's answer
# (support/fiber_storage_facts.rb; P5-72 and the checklist's floor decision). The file is
# `logging_matrix_facts_test.rb` because 5c's `tracing_matrix_facts_test.rb` and 5a's
# `matrix_facts_test.rb` sit beside it; one path per lane.
#
# Split into nested classes under Metrics/ClassLength, one per fact family.
class DexpaceInstrumentationLoggingMatrixFactsTest < DexpaceTestCase
  include FiberStorageFacts

  SLOT = :"dexpace.logging.fact"
  OTHER = :"dexpace.logging.other"
  FLOOR = ::Gem::Version.new(::RUBY_VERSION) < ::Gem::Version.new("3.3")

  def teardown
    ::Fiber[SLOT] = nil
    ::Fiber[OTHER] = nil
    super
  end

  # Fact 1: the per-key write is warning-free on every row, and `= nil` deletes from 3.3 only.
  test "fact 1: Fiber[]= writes with no warning; = nil deletes from 3.3 and retains on 3.2" do
    warnings = WarningCapture.record do
      ::Fiber[SLOT] = 123
      ::Fiber[SLOT] = nil
    end

    assert_empty(warnings)
    assert_nil(::Fiber[SLOT])
    assert_equal(!FLOOR, NIL_ASSIGNMENT_DELETES, "the boundary is 3.3.0")
    assert_diagnostic_key_removed(SLOT)
  end

  # Fact 1, the whole-map half: the setter warns per call and is the one constructor of a
  # nil-valued key on 3.3+, which is the input OBS-10's null-skip is about. Core never calls it.
  test "fact 1: Fiber#storage= warns on every call and refuses a String key" do
    before = ::Fiber.current.storage
    warnings = WarningCapture.record do
      ::Fiber.current.storage = before.merge(SLOT => nil)
      assert_raises(::TypeError) { ::Fiber.current.storage = { "string" => 1 } }
    end

    assert_equal(2, warnings.size)
    assert_match(/Fiber#storage= is experimental/, warnings.first)
    assert(::Fiber.current.storage.key?(SLOT))
    assert_nil(::Fiber[SLOT])
  ensure
    WarningCapture.record { ::Fiber.current.storage = before }
  end

  # Fact 2: capture has nothing to duplicate, and an opted-out fiber reads nil from 3.3 -- and
  # `{}` on the 3.2 floor, which is why Diagnostics.capture normalises both to an empty Hash.
  test "fact 2: storage is a fresh unfrozen copy per read; storage: nil reads nil, {} on 3.2" do
    first = ::Fiber.current.storage

    refute_same(first, ::Fiber.current.storage)
    refute_predicate(first, :frozen?)

    first[SLOT] = :injected

    assert_nil(::Fiber[SLOT], "mutating the copy changes nothing")

    opted_out = ::Fiber.new(storage: nil) { ::Fiber.current.storage }.resume
    if FLOOR
      assert_equal({}, opted_out)
    else
      assert_nil(opted_out)
    end
  end

  # Fact 3: the per-key union restore is exact on 3.3+ and leaves a snapshot-introduced key
  # present-with-nil on the floor -- the one residual OBS-24's bridge has there (P5-72).
  test "fact 3: the per-key union restore is exact from 3.3 and nil-retaining on 3.2" do
    ::Fiber[SLOT] = "prior"
    prior = ::Fiber.current.storage
    snapshot = { SLOT => "installed", OTHER => "introduced" }
    snapshot.each { |key, value| ::Fiber[key] = value }

    assert_equal("installed", ::Fiber[SLOT])

    (prior.keys | snapshot.keys).each { |key| ::Fiber[key] = prior[key] }

    assert_equal("prior", ::Fiber[SLOT])
    assert_nil(::Fiber[OTHER])
    assert_diagnostic_key_removed(OTHER)
    assert_equal(NIL_ASSIGNMENT_DELETES, ::Fiber.current.storage == prior,
                 "exact iff = nil deletes",)
  end

  test "the DiagnosticContext helper restores every key the block touched" do
    ::Fiber[SLOT] = "outside"
    DiagnosticContext.preserve do
      ::Fiber[SLOT] = "inside"
      ::Fiber[OTHER] = "introduced"
    end

    assert_equal("outside", ::Fiber[SLOT])
    assert_nil(::Fiber[OTHER])
    assert_diagnostic_key_removed(OTHER)
  end

  # Facts 6 and 7: the pinned parser's parse and rebuild behaviour the redactor is written
  # against, identical on every row.
  class ParserFacts < DexpaceTestCase
    PARSER = ::URI::RFC3986_PARSER

    test "fact 6: the parser raises on some inputs and accepts %FF, an empty query, a fragment ?" do
      ["not a url", "https://h/a b", "https://h/x?a=%zz"].each do |input|
        assert_raises(::URI::InvalidURIError, input) { PARSER.parse(input) }
      end
      assert_equal("a=%FF", PARSER.parse("https://h/x?a=%FF").query)
      assert_equal("", PARSER.parse("https://h/x?").query)
      assert_nil(PARSER.parse("/cb?code=S").scheme)
      assert_equal("", PARSER.parse("/cb?").query)
      parsed = PARSER.parse("http://h/p#a?b=c")

      assert_nil(parsed.query)
      assert_equal("a?b=c", parsed.fragment)
      assert_equal("", PARSER.parse("#frag").path)
    end

    test "fact 6: component assignment raises on an opaque URI and never on content" do
      opaque = PARSER.parse("mailto:support@example.com")

      assert_raises(::URI::InvalidURIError) { opaque.userinfo = "***:***" }
      assert_raises(::URI::InvalidURIError) { opaque.query = "a=1" }
      assert_nil(opaque.userinfo)
      assert_nil(opaque.query)

      uri = PARSER.parse("https://user@h/x?a=1")
      uri.userinfo = "***:***"
      uri.query = ""

      assert_equal("https://***:***@h/x?", uri.to_s)

      uri.query = nil

      assert_equal("https://***:***@h/x", uri.to_s)
    end

    test "fact 7: a decoded %FF name is invalid UTF-8; #downcase raises, #scrub does not" do
      decoded = ::URI.decode_www_form_component("%FF")

      refute_predicate(decoded, :valid_encoding?)
      error = assert_raises(::ArgumentError) { decoded.downcase }
      assert_match(/invalid/, error.message)
      refute_kind_of(::URI::Error, error)
      assert_equal("", decoded.scrub("").downcase)
    end
  end

  # Facts 9, 10 and 11: the byte cap, the fold's key bridge and the decode recipe.
  class RenderingFacts < DexpaceTestCase
    test "fact 9: a byte slice of a multibyte String is invalid and #scrub trims it valid" do
      sliced = ("é" * 5000).byteslice(0, 8191)

      refute_predicate(sliced, :valid_encoding?)
      scrubbed = sliced.scrub("")

      assert_predicate(scrubbed, :valid_encoding?)
      assert_equal(4095, scrubbed.length)
      assert_equal(8190, scrubbed.bytesize)
      assert_equal(10_000, ("é" * 5000)[0, 8192].bytesize, "a character cap is not 8 KiB")
    end

    test "fact 10: Symbol#name is the same frozen String on every call and #to_s is not" do
      assert_same(:"trace.id".name, :"trace.id".name)
      assert_predicate(:"trace.id".name, :frozen?)
      refute_same(:"trace.id".to_s, :"trace.id".to_s)
    end

    test "fact 11: transcoding from BINARY destroys non-ASCII bytes and retagging first does not" do
      mangled = "café".b.encode(::Encoding::UTF_8, invalid: :replace, undef: :replace)

      assert_equal("caf��", mangled)

      latin1 = "caf\xE9".b.dup.force_encoding(::Encoding::ISO_8859_1)
      retagged = latin1.encode(::Encoding::UTF_8, ::Encoding::ISO_8859_1,
                               invalid: :replace, undef: :replace,)

      assert_equal("café", retagged)
      partial = "\xE4\xBD".b.dup.force_encoding(::Encoding::UTF_8)
      truncated = partial.encode(::Encoding::UTF_8, ::Encoding::UTF_8,
                                 invalid: :replace, undef: :replace,)

      assert_equal("�", truncated)
      assert_raises(::ArgumentError) { ::Encoding.find("no-such-charset") }
    end
  end

  # The recording sink 5b's own suites read, driven red before the double existed.
  class DoublesContract < DexpaceTestCase
    test "RecordingSink satisfies the _Sink duck type and records both call forms in order" do
      sink = RecordingSink.new

      %i[debug info warn error debug? info? warn? error?].each do |name|
        assert_respond_to(sink, name)
      end
      assert_predicate(sink, :debug?)
      assert_nil(sink.info("hello"))
      assert_nil(sink.warn { "computed" })
      assert_equal(%i[info warn], sink.entries.map(&:severity))
      assert_equal(%w[hello computed], sink.payloads)
      assert_equal("hello", sink.entries[0].message)
      assert_nil(sink.entries[1].message)

      sink.clear

      assert_empty(sink.entries)
    end

    test "RecordingSink's enablement is per severity and settable after construction" do
      sink = RecordingSink.new(debug_enabled: false, info_enabled: false)

      refute_predicate(sink, :debug?)
      refute_predicate(sink, :info?)
      assert_predicate(sink, :warn?)

      sink.debug_enabled = true

      assert_predicate(sink, :debug?)
    end
  end
end
