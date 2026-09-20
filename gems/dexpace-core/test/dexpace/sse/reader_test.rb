# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/sse/reader"
require_relative "../../../lib/dexpace/io/buffered_source"
require_relative "../../support/fake_chunked"
require_relative "../../support/fake_byte_source"

# Exercises: SSE-1, SSE-3 through SSE-18 and SSE-19's event cap -- the field state machine over
# the line machine. Every fixture string in the FieldTest below is taken verbatim from the
# conformance clause of the requirement its test names, in
# docs/product-spec/13-server-sent-events-and-streaming.md. Split under Metrics/ClassLength: the
# field grammar and the BOM (Task 5), SSE-11's retry screen (Task 6 -- a SEPARATE cap from
# SSE-19's line cap and a separate checklist row, which is why its tests sit apart), and
# dispatch, end-of-stream, statefulness, ownership and the event cap (Task 7).
class DexpaceSSEReaderTest < DexpaceTestCase
  Reader = Dexpace::SSE::Reader

  # The helpers every nested case shares.
  module Fixtures
    def source(bytes)
      Dexpace::IO::BufferedSource.of_bytes(bytes.b)
    end

    def first_event(bytes, **)
      Reader.new(source(bytes), **).next_event
    end

    def events(bytes, **)
      reader = Reader.new(source(bytes), **)
      out = []
      while (event = reader.next_event)
        out << event
      end
      out
    end
  end

  # SSE-3 through SSE-10 and SSE-12: the field grammar, byte-level, and the BOM lookahead.
  class FieldTest < DexpaceTestCase
    include Fixtures

    test "SSE-3: a colon-less line is a field name with an empty value" do
      assert_equal([""], first_event("data\n\n").data)
    end

    test "SSE-3: a trailing colon yields an empty value" do
      assert_equal([""], first_event("data:\n\n").data)
    end

    test "SSE-3: an unrecognized field with no colon dispatches no event" do
      assert_nil(first_event("garbage\n\n"))
    end

    test "SSE-3: the split is at the FIRST colon; later colons are value bytes" do
      assert_equal(["a:b:c"], first_event("data:a:b:c\n\n").data)
      assert_equal("t:1", first_event("id:t:1\ndata:x\n\n").id)
    end

    test "SSE-4: a present empty event name is present, not absent" do
      assert_equal("", first_event("event:\ndata:x\n\n").event)
    end

    test "SSE-4: a present empty id is present, not absent, and dispatches on its own" do
      event = first_event("id:\n\n")

      refute_nil(event)
      assert_equal("", event.id)
    end

    test "SSE-5: exactly one leading space is stripped and further spaces are preserved" do
      assert_equal(["hello"], first_event("data: hello\n\n").data)
      assert_equal(["  hello"], first_event("data:   hello\n\n").data)
    end

    test "SSE-5: only U+0020 is stripped -- a tab after the colon is value content" do
      assert_equal(["\thello"], first_event("data:\thello\n\n").data)
    end

    test "SSE-6: a comment line is captured and counts as a field seen on its own" do
      event = first_event(":keep-alive\n\n")

      assert_equal("keep-alive", event.comment)
      assert_empty(event.data)
    end

    test "SSE-6: comments are latest-wins within a block, and strip one leading space" do
      assert_equal("second", first_event(":first\n:second\ndata:x\n\n").comment)
      assert_equal(" spaced", first_event(":  spaced\n\n").comment)
      assert_equal("", first_event(":\n\n").comment)
    end

    test "SSE-7: an unknown field sets no state and causes no dispatch on its own" do
      event = first_event("garbage: zzz\nevent: kept\ndata: p\n\n")

      assert_equal("kept", event.event)
      assert_equal(["p"], event.data)
      assert_nil(event.id)
      assert_nil(event.comment)
      assert_nil(first_event("garbage: zzz\n\n"))
    end

    test "SSE-7/P7-24: field names are compared CASE-SENSITIVELY, so DATA: is an unknown field" do
      # WHATWG compares field names exactly and SSE-7 names four lowercase tokens, requiring every
      # other name be silently discarded. A downcase here would make DATA: an interpreted data
      # field. This is the charter's spec-forced boundary 19 having no site in 7b.
      assert_nil(first_event("DATA: x\n\n"))
      assert_nil(first_event("Event: x\n\n"))
      assert_nil(first_event("Id: x\n\n"))
      assert_nil(first_event("RETRY: 5\n\n"))
    end

    test "SSE-7: a field name with surrounding space is not one of the four" do
      assert_nil(first_event(" data: x\n\n"))
      assert_nil(first_event("data : x\n\n"))
    end

    test "SSE-8: consecutive data fields accumulate in wire order, unjoined" do
      assert_equal(%w[line1 line2], first_event("data: line1\ndata: line2\n\n").data)
    end

    test "SSE-9: an id containing a NUL is ignored entirely" do
      assert_nil(first_event("id: a\0b\ndata:x\n\n").id)
    end

    test "SSE-9: a NUL id does not overwrite a valid id already seen in the same block" do
      assert_equal("good", first_event("id: good\nid: a\0b\ndata:x\n\n").id)
    end

    test "SSE-9: a valid id is stored verbatim, latest-wins" do
      assert_equal("second", first_event("id: first\nid: second\ndata:x\n\n").id)
      assert_equal(" spaced ", first_event("id:  spaced \ndata:x\n\n").id)
    end

    test "SSE-9: the NUL screen runs on the raw bytes, so a NUL is never lost to a replacement" do
      # An invalid UTF-8 byte beside the NUL: decoded first, the NUL would still be there, but the
      # screen must not depend on the decode at all.
      assert_nil(first_event("id: \xFF\0\ndata:x\n\n").id)
    end

    test "SSE-10: an absent event field is absent and is never defaulted to 'message'" do
      assert_nil(first_event("data:x\n\n").event)
    end

    test "SSE-10: the event field is raw and latest-wins" do
      assert_equal("second", first_event("event: first\nevent: second\ndata:x\n\n").event)
      assert_equal("Message", first_event("event: Message\ndata:x\n\n").event)
    end
  end

  # SSE-12: the BOM lookahead, P7-26's decode and P7-27's duck.
  class LookaheadTest < DexpaceTestCase
    include Fixtures

    test "SSE-12: a single leading BOM is consumed and excluded from the first event's fields" do
      assert_equal(["x"], first_event("\xEF\xBB\xBFdata: x\n\n").data)
    end

    test "SSE-12: a BOM later in the stream survives as ordinary data" do
      assert_equal(["a\u{FEFF}b"], first_event("data: a\u{FEFF}b\n\n").data)
      # At the head of a later line the preserved BOM bytes make the field name "\xEF\xBB\xBFdata",
      # an unknown field: nothing dispatches from it, where a consumed BOM would have given "b".
      assert_equal([["a"]], events("data: a\n\n\xEF\xBB\xBFdata: b\n\n").map(&:data))
    end

    test "SSE-12: only ONE leading BOM is consumed" do
      assert_equal("1", first_event("\xEF\xBB\xBFid: 1\n\n").id)
      assert_empty(events("\xEF\xBB\xBF\xEF\xBB\xBFid: 1\n\n"),
                   "the second BOM is a field name's bytes",)
    end

    test "SSE-12: a non-BOM prefix is left intact -- the lookahead is non-consuming" do
      # A reader that consumed three bytes unconditionally would pass every BOM-prefixed fixture
      # and corrupt every stream without one: it would turn "xyzdata: y" into the valid line
      # "data: y" and dispatch it, and "data: xyz" into the unknown field "a".
      assert_equal(["xyz"], first_event("data: xyz\n\n").data)
      assert_empty(events("xyzdata: y\n\n"))
    end

    test "SSE-12: a two-byte BOM prefix is a field name's bytes, not a consumed BOM" do
      # "\xEF\xBBx" is a prefix of the BOM and not the BOM: nothing is consumed, so the first line
      # is the unknown field "\xEF\xBBxdata" and nothing dispatches, where a three-byte skip would
      # have dispatched "data: y".
      assert_empty(events("\xEF\xBBxdata: y\n\n"))
      assert_equal(["y"], events("\xEF\xBBdata: x\ndata: y\n\n").first.data)
    end

    test "SSE-12: a stream shorter than three bytes does not confuse the lookahead" do
      assert_nil(first_event("\n"))
      assert_nil(first_event(""))
      assert_equal([""], first_event("data").data)
    end

    test "SSE-12: the BOM is consumed on the first pull, not at construction" do
      chunked = FakeChunked.new("\xEF\xBB\xBFdata: a\n\n".b)
      reader = Reader.new(Dexpace::IO::BufferedSource.over(chunked))

      assert_equal(0, chunked.yielded,
                   "a reader built and never pulled touches its source zero times",)
      assert_equal(["a"], reader.next_event.data)
    end

    test "P7-26: field values are UTF-8, decoded once with both encodings named" do
      value = first_event("data: café\n\n").data.first

      assert_equal(::Encoding::UTF_8, value.encoding)
      assert_equal("café", value)
      assert_equal("é", first_event("id: é\nevent: ü\n:ö\n\n").id)
    end

    test "P7-26: an invalid UTF-8 byte is replaced rather than raising" do
      value = first_event("data: a\xFFb\n\n").data.first

      assert_equal(::Encoding::UTF_8, value.encoding)
      assert_predicate(value, :valid_encoding?)
      assert_equal("a�b", value)
    end

    test "P7-27: the reader's source is a duck answering _ByteSource, not a BufferedSource" do
      reader = Reader.new(FakeByteSource.new("\xEF\xBB\xBFdata: x\n\ndata: y\n\n"))

      assert_equal([["x"], ["y"]], [reader.next_event.data, reader.next_event.data])
      assert_nil(reader.next_event)
    end

    test "P7-27: a source without #peek or #skip is refused by name" do
      error = assert_raises(Dexpace::InvalidArgumentError) { Reader.new(::Object.new) }

      assert_match(/getbyte.*peek.*skip/, error.message)
    end
  end

  # SSE-11: the retry field's value screen and magnitude cap. This is a SEPARATE cap from
  # SSE-19's line cap and a separate checklist row; the line-cap finding conflated the two once
  # already and the two tests sit apart deliberately.
  class RetryTest < DexpaceTestCase
    include Fixtures

    test "SSE-11: a digits-only value is accepted as a non-negative millisecond duration" do
      assert_equal(5000, first_event("retry: 5000\n\n").retry)
      assert_equal(0, first_event("retry: 0\n\n").retry)
      assert_equal(5, first_event("retry: 05\n\n").retry)
      assert_equal(5, first_event("retry:5\n\n").retry)
    end

    test "SSE-11: retry is latest-wins within a block" do
      assert_equal(2, first_event("retry: 1\nretry: 2\n\n").retry)
    end

    test "SSE-11: every non-digits-only form leaves retry unset" do
      # verified fact 1: Integer(s, exception: false) ACCEPTS six of these. This battery is the
      # reason the screen is an anchored pattern and not Integer() or #to_i.
      rejected = ["retry: bad", "retry: -100", "retry: +5", "retry:", "retry: 0x10", "retry: 1_0",
                  "retry:  5", "retry: 5a", "retry: ０５", "retry: 5 ", "retry: 5\t", "retry: 12abc",]
      rejected.each do |line|
        event = first_event("#{line}\ndata:x\n\n")

        assert_nil(event.retry,
                   "expected #{line.inspect} to be ignored",)
      end
    end

    test "SSE-11: an ignored retry does not mark the block dispatchable on its own account" do
      assert_nil(first_event("retry: bad\n\n"))
      assert_nil(first_event("retry:\n\n"))
    end

    test "SSE-11: a value above the documented cap is ignored rather than wrapped" do
      assert_nil(first_event("retry: #{Dexpace::SSE::MAX_RETRY_MS + 1}\n\n"))
      assert_equal(Dexpace::SSE::MAX_RETRY_MS,
                   first_event("retry: #{Dexpace::SSE::MAX_RETRY_MS}\n\n").retry,)
    end

    test "SSE-11: an over-cap retry does not overwrite a valid one already seen in the block" do
      over = Dexpace::SSE::MAX_RETRY_MS + 1

      assert_equal(7, first_event("retry: 7\nretry: #{over}\ndata:x\n\n").retry)
    end

    test "SSE-11: an absurdly long digit run is ignored without being parsed as an Integer" do
      assert_nil(first_event("retry: #{"9" * 4096}\n\n"))
    end
  end

  # SSE-1, SSE-9's dispatch half, SSE-13 through SSE-18 and SSE-19's event cap.
  class DispatchTest < DexpaceTestCase
    include Fixtures

    test "SSE-1: a blank line is the dispatch boundary and resets the accumulators" do
      assert_equal([["1"], ["2"]], events("data: 1\n\ndata: 2\n\n").map(&:data))
    end

    test "SSE-1/SSE-16: the second event's id is absent when only the first block carried one" do
      parsed = events("id: 1\ndata: a\n\ndata: b\n\n")

      assert_equal("1", parsed.first.id)
      assert_nil(parsed.last.id)
    end

    test "SSE-1: every accumulator resets -- event, comment and retry too" do
      parsed = events("event: e\n:c\nretry: 5\ndata: a\n\ndata: b\n\n")

      assert_equal(["e", "c", 5], [parsed.first.event, parsed.first.comment, parsed.first.retry])
      assert_equal([nil, nil, nil], [parsed.last.event, parsed.last.comment, parsed.last.retry])
    end

    test "SSE-13: an id-only block dispatches" do
      assert_equal(["42"], events("id: 42\n\n").map(&:id))
    end

    test "SSE-13: a retry-only block and a comment-only block both dispatch" do
      assert_equal(1, events("retry: 5\n\n").size)
      assert_equal(1, events(":c\n\n").size)
    end

    test "SSE-13: a block in which no field was set is skipped" do
      assert_empty(events("\n\n\n"))
      assert_equal([["a"], ["b"]], events("\n\ndata: a\n\n\n\n\ndata: b\n\n\n").map(&:data))
    end

    test "SSE-9/SSE-13: a NUL id does not count as a field seen, so its block dispatches nothing" do
      # SSE-9: the field is "ignored ENTIRELY: it does not set the id, DOES NOT COUNT AS A 'FIELD
      # SEEN', and does not overwrite a valid id already seen" (appendix C:418,
      # sse-streaming/2fec5657). Every other SSE-9 test above carries a data line, so the block
      # dispatches whatever the flag does; this is the only assertion that fails when the
      # dispatch flag is set on the field NAME before the NUL screen runs, which is the way an
      # implementation gets this wrong.
      assert_empty(events("id: a\0b\n\n"))
    end

    test "SSE-14: a partial block still present at EOF is dispatched" do
      parsed = events("data: hello")

      assert_equal(1, parsed.size)
      assert_equal(["hello"], parsed.first.data)
      assert_equal([["a"], ["b"]], events("data: a\n\ndata: b").map(&:data))
    end

    test "SSE-14: an empty stream signals end immediately with no event" do
      assert_empty(events(""))
      assert_empty(events("\n"))
    end

    test "SSE-15: the end sentinel is nil, and it is sticky" do
      reader = Reader.new(source("data: a\n\n"))

      refute_nil(reader.next_event)
      assert_nil(reader.next_event)
      assert_nil(reader.next_event)
      assert_nil(reader.next_event)
    end

    test "SSE-15: once end is reported, the source is never read again" do
      # A source whose #getbyte would answer bytes again after nil -- the way a duck could --
      # must not get the chance: end is a latch on the reader, not a re-check of the source.
      resurrecting = Class.new(FakeByteSource) do
        def getbyte
          byte = super
          return byte unless byte.nil?

          @pos = 0
          @resurrected = true
          nil
        end

        def resurrected? = @resurrected == true
      end.new("data: a\n\n")
      reader = Reader.new(resurrecting)

      refute_nil(reader.next_event)
      assert_nil(reader.next_event)
      assert_predicate(resurrecting, :resurrected?, "the first end read the source's nil")
      count = resurrecting.getbyte_count

      assert_nil(reader.next_event)
      assert_equal(count, resurrecting.getbyte_count, "the second end pulled nothing")
    end

    test "SSE-16: nothing but the BOM flag persists across calls -- no carried retry value" do
      # sse-streaming/2dba42b0 and design section 7.2 both say the current retry value and the
      # last event id are per-stream state. SSE-16 says "only the BOM already consumed flag
      # persists" and SSE-38 says the last-event-id MUST NOT be persisted. These assert the
      # requirements (the checklist's sse-streaming note).
      parsed = events("retry: 500\ndata: a\n\ndata: b\n\n")

      assert_equal(500, parsed.first.retry)
      assert_nil(parsed.last.retry)
    end

    test "SSE-16/SSE-38: no last-event-id is carried forward" do
      parsed = events("id: 1\ndata: a\n\ndata: b\n\nid: 3\ndata: c\n\n")

      assert_equal(["1", nil, "3"], parsed.map(&:id))
    end

    test "SSE-16: the BOM flag DOES persist, so a second block's leading BOM is not consumed" do
      # A reader that re-ran the lookahead on every pull would consume the second BOM and dispatch
      # "data: b"; with the flag persisting the second line is an unknown field, "\xEF\xBB\xBFdata".
      assert_equal([["a"]], events("\xEF\xBB\xBFdata: a\n\n\xEF\xBB\xBFdata: b\n\n").map(&:data))
    end

    test "SSE-17: the reader never closes its source, driven to completion" do
      src = source("data: a\n\ndata: b\n\n")
      reader = Reader.new(src)
      reader.next_event while reader.next_event

      refute_predicate(src, :closed?)
      refute_respond_to(reader, :close, "the reader has no close to offer")
    end

    test "SSE-18: the reader holds no lock -- documented single-threaded, by omission" do
      # No assertion distinguishes "documented single-threaded" from "accidentally
      # single-threaded"; this pins the omission so a Mutex is not added without a decision.
      reader = Reader.new(source("data: a\n\n"))

      refute(reader.instance_variables.any? do |name|
        reader.instance_variable_get(name).is_a?(::Thread::Mutex)
      end)
    end
  end

  # SSE-19: the event cap and the caps' wiring.
  class EventCapTest < DexpaceTestCase
    include Fixtures

    test "SSE-19: an event block whose accumulated bytes cross the cap raises" do
      cap = 32

      assert_equal(1, events("data: #{"x" * 20}\n\n", max_event_bytes: cap).size)
      error = assert_raises(Dexpace::SSE::LimitExceededError) do
        events("data: #{"x" * 20}\ndata: #{"y" * 20}\n\n", max_event_bytes: cap)
      end

      assert_equal(:event, error.kind)
      assert_equal(cap, error.limit)
    end

    test "SSE-19: the event byte total resets at each dispatch" do
      cap = 32
      parsed = events("data: #{"x" * 20}\n\ndata: #{"y" * 20}\n\n", max_event_bytes: cap)

      assert_equal(2, parsed.size)
    end

    test "SSE-19/SSE-1: the event byte total resets at every blank line, dispatching or not" do
      # A blank line ends a block whether or not a field was seen (SSE-1), so a run of fieldless
      # blocks -- unknown-field keep-alives (SSE-7), NUL ids (SSE-9), rejected retries (SSE-11)
      # -- is a run of blocks and never one block: three 5-byte `zz: 1` blocks under a 12-byte
      # cap must not add up to a spurious LimitExceededError before `data: b` arrives. Review
      # round 0's R0-1: dispatch's nil branch returned before the reset.
      wire = "data: a\n\n#{"zz: 1\n\n" * 3}data: b\n\n"

      assert_equal([["a"], ["b"]], events(wire, max_event_bytes: 12).map(&:data))
      assert_equal(1, events("#{"id: a\0b\n\n" * 6}data: b\n\n", max_event_bytes: 32).size)
      assert_equal(1, events("#{"retry: -1\n\n" * 6}data: b\n\n", max_event_bytes: 32).size)
      # The same lines in ONE block still trip the cap: the reset is per blank line, not per line.
      assert_raises(Dexpace::SSE::LimitExceededError) do
        events("#{"zz: 1\n" * 3}data: b\n\n", max_event_bytes: 12)
      end
    end

    test "SSE-19: the event total counts every line of the block, comments and unknowns included" do
      # 2^20 one-byte data lines is the surface appendix C names; the count is the block's raw
      # line bytes, so a block padded with comments or unknown fields cannot slip under it.
      assert_raises(Dexpace::SSE::LimitExceededError) do
        events("#{":#{"c" * 20}\n" * 2}data: x\n\n", max_event_bytes: 32)
      end
      assert_raises(Dexpace::SSE::LimitExceededError) do
        events("#{"zz: #{"c" * 20}\n" * 2}data: x\n\n", max_event_bytes: 32)
      end
      assert_equal(1, events("#{"data: x\n" * 4}\n", max_event_bytes: 32).size)
    end

    test "SSE-19: a block of exactly the cap passes and one byte more raises" do
      cap = 32

      assert_equal(1, events("data: #{"x" * 10}\ndata: #{"y" * 10}\n\n", max_event_bytes: cap).size)
      assert_raises(Dexpace::SSE::LimitExceededError) do
        events("data: #{"x" * 10}\ndata: #{"y" * 11}\n\n", max_event_bytes: cap)
      end
    end

    test "SSE-19: at the real defaults, a block of MAX_EVENT_BYTES passes and one more raises" do
      # The assertions name the constants, never the literals, so a second constant would break
      # this test rather than pass it. The one place 7b parses at scale -- 8 MiB twice per run per
      # matrix row, a decision rather than an accident -- and it runs over the duck source, whose
      # #getbyte is three method calls where BufferedSource's is a dozen and a String allocation
      # (0.3 vs 0.9 microseconds a byte on 4.0.6): the caps under test are the reader's, not the
      # source's, and P7-27 makes the duck a conforming source.
      cap = Dexpace::SSE::MAX_EVENT_BYTES
      line = Dexpace::SSE::MAX_LINE_BYTES - 6 # "data: " plus the payload is one full line
      block = "data: #{"x" * line}\n" * 8

      # The count is of line CONTENT, terminators stripped: eight full lines are exactly the cap.
      assert_equal(cap, 8 * Dexpace::SSE::MAX_LINE_BYTES)
      assert_equal(cap + 8, block.bytesize)
      assert_equal(8, Reader.new(FakeByteSource.new("#{block}\n")).next_event.data.size)
      assert_raises(Dexpace::SSE::LimitExceededError) do
        Reader.new(FakeByteSource.new("#{block}data: y\n\n")).next_event
      end
    end

    test "SSE-19: the line cap reaches the reader through its own keyword" do
      error = assert_raises(Dexpace::SSE::LimitExceededError) do
        events("data: #{"x" * 64}\n\n", max_line_bytes: 32)
      end

      assert_equal(:line, error.kind)
    end

    test "SSE-19: both caps default to their constants, and both must be positive Integers" do
      reader = Reader.new(source(""))

      assert_equal(Dexpace::SSE::MAX_LINE_BYTES, reader.max_line_bytes)
      assert_equal(Dexpace::SSE::MAX_EVENT_BYTES, reader.max_event_bytes)
      assert_raises(Dexpace::InvalidArgumentError) { Reader.new(source(""), max_event_bytes: 0) }
      assert_raises(Dexpace::InvalidArgumentError) { Reader.new(source(""), max_line_bytes: -1) }
    end
  end
end
