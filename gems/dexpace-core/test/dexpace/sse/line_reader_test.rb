# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/sse"
require_relative "../../../lib/dexpace/sse/line_reader"
require_relative "../../../lib/dexpace/io/buffered_source"
require_relative "../../support/scripted_chunked"
require_relative "../../support/fake_byte_source"

# Exercises: SSE-2 (LF, CR and CRLF all recognised, CRLF as a single terminator, terminators
# stripped, a lone CR terminating alone), SSE-14 (a final line with no terminator returned as
# content), SSE-17 (the line reader closes nothing), SSE-19 (the line cap, rejecting loudly and
# before materialising); P7-20 and P7-27.
#
# P7-20: these tests are the whole reason this class exists rather than a call to phase 3a's
# #read_line_utf8. IO-14 requires a lone \r be KEPT AS CONTENT and SSE-2 requires it TERMINATE --
# the "lone CR" test below is exactly the assertion phase 3a's own suite makes in the opposite
# direction (docs/work/mvp/phase3/phase3a/2026-09-08-phase3a-io-contracts.md:2201). Split under
# Metrics/ClassLength: the grammar, the cap and the contract.
class DexpaceSSELineReaderTest < DexpaceTestCase
  LineReader = Dexpace::SSE::LineReader

  # The helpers every nested case shares.
  module Fixtures
    def source(bytes)
      Dexpace::IO::BufferedSource.of_bytes(bytes.b)
    end

    def lines(bytes, **)
      reader = LineReader.new(source(bytes), **)
      out = []
      while (line = reader.next_line)
        out << line
      end
      out
    end
  end

  # SSE-2 and SSE-14: the three terminators and the unterminated tail.
  class GrammarTest < DexpaceTestCase
    include Fixtures

    test "SSE-2: LF terminates and is stripped" do
      assert_equal(%w[one two], lines("one\ntwo\n"))
    end

    test "SSE-2: CRLF is a single terminator, not two" do
      assert_equal(%w[one two], lines("one\r\ntwo\r\n"))
    end

    test "SSE-2: a lone CR terminates a line by itself" do
      # IO-14's #read_line_utf8 answers "a\rb" here (phase 3a's own assertion); SSE-2: two lines.
      assert_equal(%w[a b], lines("a\rb\r"))
    end

    test "SSE-2: a CR followed by a non-LF byte terminates, and that byte starts the next line" do
      assert_equal(%w[a b], lines("a\rb\n"))
      assert_equal(%w[a bc], lines("a\rbc"))
    end

    test "SSE-2: mixed terminators produce the same line list" do
      assert_equal(%w[a b c], lines("a\nb\r\nc\r"))
      assert_equal(%w[a b c], lines("a\r\nb\rc\n"))
    end

    test "SSE-2: the same lines under each terminator and under a mix are identical" do
      expected = ["data: 1", "id: x", "", "data: 2", ""]

      ["\n", "\r\n", "\r"].each do |terminator|
        assert_equal(expected, lines(expected.map { |line| "#{line}#{terminator}" }.join),
                     terminator.inspect,)
      end
    end

    test "SSE-2: a bare terminator yields an empty line, which is the dispatch boundary" do
      assert_equal(["a", "", "b"], lines("a\n\nb\n"))
      assert_equal(["a", "", "b"], lines("a\r\n\r\nb\r\n"))
      assert_equal(["a", "", "b"], lines("a\r\rb\r"))
    end

    test "SSE-2: CR CR LF is two terminators -- an empty line, then CRLF" do
      assert_equal(["a", ""], lines("a\r\r\n"))
    end

    test "SSE-14: a final line with no terminator comes back as content" do
      assert_equal(%w[a tail], lines("a\ntail"))
    end

    test "SSE-2/SSE-14: a stream ending in a lone CR terminates that line and nothing follows" do
      assert_equal(["a"], lines("a\r"))
    end

    test "returns nil when exhausted before any byte, and stays nil" do
      reader = LineReader.new(source(""))

      assert_nil(reader.next_line)
      assert_nil(reader.next_line)
    end

    test "lines are BINARY, and a non-ASCII line stays BINARY" do
      # An ASCII-only fixture passes under exactly the bug io-and-byte-streams/a44b4de6 names, so
      # this assertion uses non-ASCII content deliberately.
      line = lines("café\n").first

      assert_equal(::Encoding::BINARY, line.encoding)
      assert_equal("café".b, line)
    end

    test "each line is a fresh frozen String, never the reader's reused buffer" do
      reader = LineReader.new(source("one\ntwo\n"))
      first = reader.next_line
      second = reader.next_line

      assert_predicate(first, :frozen?)
      refute_same(first, second)
      assert_equal("one".b, first, "the second read did not overwrite the first line")
    end

    # SSE-2's exhaustiveness claim in executable form (testing/7ece0212): the seed is pinned
    # and printed on failure by DexpaceTestCase#sample, and a lone-CR-before-a-non-LF-byte or a
    # CR-at-the-end bug in the pushback surfaces here. One sequence the generator never emits,
    # because the grammar itself cannot express it: an EMPTY line terminated by LF directly after
    # a CR-terminated line -- "\r" + "" + "\n" is the bytes "\r\n", which SSE-2 reads as ONE
    # terminator (CRLF), so that assignment has no distinct parse to round-trip to.
    test "SSE-2 property: any line list under any terminator assignment parses back to itself" do
      terminators = ["\n", "\r\n", "\r"]
      alphabet = %w[a b : d é x 0]
      sample(count: 200, seed: 20_260_920) do |rng|
        count = rng.rand(0..6)
        generated = Array.new(count) do
          Array.new(rng.rand(0..5)) do
            alphabet.sample(random: rng)
          end.join
        end
        previous = nil
        bytes = generated.map do |line|
          choices = previous == "\r" && line.empty? ? ["\r\n", "\r"] : terminators
          previous = choices.sample(random: rng)
          "#{line}#{previous}"
        end.join
        # A trailing unterminated line, half the time (SSE-14).
        if rng.rand < 0.5
          tail = Array.new(rng.rand(1..3)) { alphabet.sample(random: rng) }.join
          generated << tail
          bytes += tail
        end

        assert_equal(generated.map(&:b), lines(bytes), bytes.inspect)
      end
    end
  end

  # SSE-19: the line cap.
  class CapTest < DexpaceTestCase
    include Fixtures

    test "SSE-19: a line of exactly the cap passes and one byte more raises" do
      cap = 64

      assert_equal(["x" * cap], lines("#{"x" * cap}\n", max_line_bytes: cap))
      error = assert_raises(Dexpace::SSE::LimitExceededError) do
        lines("#{"x" * (cap + 1)}\n", max_line_bytes: cap)
      end

      assert_equal(:line, error.kind)
      assert_equal(cap, error.limit)
    end

    test "SSE-19: the cap counts BYTES, so a multi-byte character cannot slip it" do
      # "é" is two bytes: three of them are six bytes, one over a five-byte cap.
      assert_equal(["éé".b], lines("éé\n", max_line_bytes: 5))
      assert_raises(Dexpace::SSE::LimitExceededError) { lines("ééé\n", max_line_bytes: 5) }
    end

    test "SSE-19: the cap defaults to MAX_LINE_BYTES" do
      assert_equal(Dexpace::SSE::MAX_LINE_BYTES, LineReader.new(source("")).max_line_bytes)
      assert_equal(64, LineReader.new(source(""), max_line_bytes: 64).max_line_bytes)
    end

    test "SSE-19: the cap rejects before materialising, not after" do
      # A source that would supply far more than the cap is stopped at the cap, so the bytes
      # pulled are bounded by it. This is what distinguishes a guard from an after-the-fact length
      # check. ScriptedChunked yields one byte per chunk, so its yield count IS the byte count.
      chunked = ScriptedChunked.new(*(["x"] * 10_000))
      reader = LineReader.new(Dexpace::IO::BufferedSource.over(chunked), max_line_bytes: 64)

      assert_raises(Dexpace::SSE::LimitExceededError) { reader.next_line }
      assert_operator(chunked.yielded, :<=, 65)
    end

    test "SSE-19: at the real default, a line of MAX_LINE_BYTES passes and one more byte raises" do
      # The assertions name the constant, never the literal, so a second constant would break
      # this test rather than pass it. Parsed at scale -- 1 MiB twice per run -- over the duck
      # source, whose #getbyte is a third the cost of BufferedSource's (reader_test.rb says why).
      cap = Dexpace::SSE::MAX_LINE_BYTES

      assert_equal(cap, LineReader.new(FakeByteSource.new("#{"x" * cap}\n")).next_line.bytesize)
      assert_raises(Dexpace::SSE::LimitExceededError) do
        LineReader.new(FakeByteSource.new("#{"x" * (cap + 1)}\n")).next_line
      end
    end

    test "SSE-19: the cap must be a positive Integer" do
      [0, -1, 1.5, "64", nil].each do |bad|
        assert_raises(Dexpace::InvalidArgumentError, bad.inspect) do
          LineReader.new(source(""), max_line_bytes: bad)
        end
      end
    end
  end

  # SSE-17 and P7-27: what the line reader holds its source to.
  class ContractTest < DexpaceTestCase
    include Fixtures

    test "SSE-17: the line reader never closes its source, driven to completion" do
      src = source("a\nb")
      reader = LineReader.new(src)
      reader.next_line while reader.next_line

      refute_predicate(src, :closed?)
    end

    test "P7-27: the source is a duck answering _ByteSource, not a BufferedSource" do
      reader = LineReader.new(FakeByteSource.new("x\ny"))

      assert_equal(%w[x y], [reader.next_line, reader.next_line])
      assert_nil(reader.next_line)
    end

    test "P7-27: a source without #getbyte is refused by name" do
      error = assert_raises(Dexpace::InvalidArgumentError) { LineReader.new(::Object.new) }

      assert_match(/getbyte/, error.message)
    end

    test "SSE-2: a lone CR at the end of one pull is resolved by the next byte, not by a timeout" do
      # The grammar's inherent property: CR cannot be dispatched until one further byte arrives,
      # because nothing distinguishes it from the first half of CRLF. The line comes back once the
      # next byte does, and that byte is kept for the following line.
      chunked = ScriptedChunked.new("a\r", "b\n")
      reader = LineReader.new(Dexpace::IO::BufferedSource.over(chunked))

      assert_equal("a".b, reader.next_line)
      assert_equal(2, chunked.yielded, "the second chunk was pulled to resolve the CR")
      assert_equal("b".b, reader.next_line)
    end
  end
end
