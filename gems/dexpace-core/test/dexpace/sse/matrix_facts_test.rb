# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"
require_relative "../../support/fake_chunked"
require_relative "../../support/scripted_chunked"

# Exercises: SSE-2, SSE-11, SSE-12, SSE-20, SSE-24, SSE-25, SSE-29, SSE-31, SSE-39 (the Ruby
# facts they rest on) -- the phase-7b design's eight verified facts plus the ones the build found
# against 3a's shipped BufferedSource, re-run as a standing test on every CI row rather than once
# in a scratch script (5a's, 5b's, 5c's, 6a's, 6b's and 6c's precedent). Run on 3.2.11, 3.3.12,
# 3.4.10 and 4.0.6 on 2026-09-20: every fact holds identically on every row except the one this
# file pins against RUBY_VERSION -- Data#with skipping an #initialize override on the 3.2 floor,
# which is why Event includes Dexpace::Model (data-modeling/83610619). No lib/ mirror: it asserts
# the interpreter and phase 3a's code, not a phase-7b file.
class DexpaceSSEMatrixFactsTest < DexpaceTestCase
  BufferedSource = Dexpace::IO::BufferedSource

  # The parked-thread helper the two SSE-31 cases share.
  module Parking
    # A thread parked inside `block`, sequenced through a Queue and then polled to "sleep" -- 3a's
    # IO-38 shape, never a timed sleep.
    def park
      started = ::Thread::Queue.new
      thread = ::Thread.new do
        started << :ready
        begin
          yield
          :returned
        rescue ::StandardError => error
          error
        end
      end
      started.pop
      ::Thread.pass until thread.status == "sleep" || !thread.status
      thread
    end
  end

  # Facts 1 through 6: the interpreter alone.
  class InterpreterTest < DexpaceTestCase
    test "SSE-11 fact 1: Integer(s, exception: false) accepts six inputs the requirement ignores" do
      accepted = ["+5", "-5", "0x10", "1_0", " 5", "5\n"].map { |s| Integer(s, exception: false) }

      assert_equal([5, -5, 16, 10, 5, 5], accepted)
      assert_equal(12, "12abc".to_i)
    end

    test "SSE-11 fact 1: an anchored digits-only pattern rejects all nine, matches BINARY digits" do
      screen = Regexp.new("\\A[0-9]+\\z", timeout: 1.0)
      rejected = ["+5", "-5", "0x10", "1_0", " 5", "5\n", "", "5a", "０５"]

      assert(rejected.none? { |s| screen.match?(s) }, "an input slipped the screen")
      assert_match(screen, "5000".b)
    end

    test "fact 2: force_encoding raises FrozenError on a frozen String even to its own encoding" do
      assert_raises(::FrozenError) { "x".b.freeze.force_encoding(::Encoding::BINARY) }
      copy = "x".b

      refute_predicate(copy, :frozen?)
      assert_equal(::Encoding::BINARY, copy.encoding)
    end

    test "fact 3: appending non-ASCII UTF-8 to a BINARY accumulator silently retags it" do
      assert_equal(::Encoding::UTF_8, ((+"".b) << "é").encoding)
      assert_equal(::Encoding::BINARY, ((+"".b) << "x").encoding)
      assert_equal(::Encoding::BINARY, ((+"".b) << "é".b).encoding)
    end

    test "SSE-20 fact 5: Data#with shares members; an #initialize override runs from 3.3 only" do
      with_member = Data.define(:data)
      list = ["x"]

      assert_same(list, with_member.new(data: list).with(data: list).data)

      seen = Class.new(Data.define(:value)) do
        def initialize(value:)
          @seen = true
          super
        end
      end
      derived = seen.new(value: 1).with(value: 2)
      if RUBY_VERSION < "3.3"
        assert_nil(derived.instance_variable_get(:@seen), "3.2 skips the override")
      else
        assert(derived.instance_variable_get(:@seen))
      end
    end

    test "SSE-24/SSE-25 fact 6: an abandoned Enumerator and an abandoned #each never run ensure" do
      ran = false
      enumerator = Enumerator.new do |yielder|
        yielder << 1
        yielder << 2
      ensure
        ran = true
      end
      enumerator.next
      2.times { GC.start }

      refute(ran)

      owner = Class.new do
        attr_reader :ran, :block_given

        def each
          @block_given = block_given?
          yield 1
          yield 2
        ensure
          @ran = true
        end
      end.new
      owner.to_enum(:each).next
      2.times { GC.start }

      refute(owner.ran)
      assert(owner.block_given, "block_given? is TRUE inside #each reached through to_enum")
    end
  end

  # Fact 7 and SSE-31's shape B, against IO.pipe and phase 3a's wrapping source.
  class ThreadTest < DexpaceTestCase
    include Parking

    test "SSE-31 fact 7: closing an IO.pipe's READ end raises IOError in a parked reader" do
      reader, writer = ::IO.pipe
      thread = park { reader.readpartial(16) }
      reader.close

      assert_kind_of(::IOError, thread.value)
      refute_kind_of(::EOFError, thread.value)
      writer.close
    end

    test "SSE-31 fact 7: closing the WRITE end instead is a clean EOFError" do
      reader, writer = ::IO.pipe
      thread = park { reader.readpartial(16) }
      writer.close

      assert_kind_of(::EOFError, thread.value)
      reader.close
    end

    test "SSE-31: a parked #getbyte through a wrapping source; source.close from another thread" do
      reader, writer = ::IO.pipe
      source = BufferedSource.wrapping(reader)
      thread = park { source.getbyte }
      source.close

      assert_kind_of(::IOError, thread.value)
      assert_predicate(source, :closed?)
      assert_predicate(reader, :closed?, "IO-6: the wrapping source closed the pipe's read end")
      writer.close
    end
  end

  # Fact 8 and the facts the build found against phase 3a's shipped code and phase 2's latch.
  class SourceTest < DexpaceTestCase
    BufferedSource = Dexpace::IO::BufferedSource

    test "SSE-12 fact 8: the UTF-8 BOM is three bytes; a capacity-sized BINARY buffer is BINARY" do
      assert_equal([239, 187, 191], "\u{FEFF}".bytes)
      assert_equal(::Encoding::BINARY, String.new(capacity: 16, encoding: ::Encoding::BINARY).encoding)
    end

    test "SSE-12 (open question 2): a #peek view read three bytes and closed disturbs nothing" do
      source = BufferedSource.of_bytes("hello".b)
      view = source.peek
      looked = Array.new(3) { view.getbyte }
      view.close

      assert_equal("hel".bytes, looked)
      assert_equal("hello".bytes, Array.new(5) { source.getbyte })

      short = BufferedSource.of_bytes("ab".b)
      short_view = short.peek

      assert_equal([97, 98, nil], [short_view.getbyte, short_view.getbyte, short_view.getbyte])
      short_view.close

      assert_equal(97, short.getbyte)
    end

    test "SSE-12: #skip(3) on a shorter source raises EndOfStreamError; the peek must come first" do
      assert_raises(Dexpace::EndOfStreamError) { BufferedSource.of_bytes("ab".b).skip(3) }
    end

    test "SSE-27: a read on a CLOSED source raises ClosedError, a StandardError, not an IOError" do
      source = BufferedSource.of_bytes("ab".b)
      source.close

      assert_raises(Dexpace::ClosedError) { source.getbyte }
      refute_operator(Dexpace::ClosedError, :<, ::IOError)
    end

    test "SSE-39 (open question 3): a BufferedSource over a chunked body pulls a chunk per event" do
      chunked = FakeChunked.new("data: a\n\n", "data: b\n\n")
      source = BufferedSource.over(chunked)
      view = source.peek
      3.times { view.getbyte }
      view.close
      9.times { source.getbyte }

      assert_equal(1, chunked.yielded, "a 3-byte lookahead plus one event's nine bytes")
      source.getbyte

      assert_equal(2, chunked.yielded, "the tenth byte pulls the second chunk")
    end

    test "SSE-29: a scripted chunked delivers every byte before its Exception and then raises" do
      source = BufferedSource.over(ScriptedChunked.new("data: a\n\n", Dexpace::StreamError.new("boom")))

      assert_equal("data: a\n\n".bytes, Array.new(9) { source.getbyte })
      assert_raises(Dexpace::StreamError) { source.getbyte }
    end

    # The cross-check's "the next #getbyte returns nil (the enumerator is finished)" is FALSE on
    # every row: Enumerator#next on a fiber that died by exception starts #each over, so the pull
    # after a mid-stream failure re-delivers the FIRST chunk's first byte. Phase 3a's residue,
    # routed (the checklist's Findings routed); the facade never meets it because SSE-27's closed?
    # check runs before every read and the facade closed itself on the failure.
    test "after a mid-stream failure BufferedSource.over's enumerator RESTARTS instead of ending" do
      source = BufferedSource.over(ScriptedChunked.new("data: a\n\n", Dexpace::StreamError.new("boom")))
      9.times { source.getbyte }
      assert_raises(Dexpace::StreamError) { source.getbyte }

      assert_equal("d".ord, source.getbyte, "the first byte again, not nil and not a second raise")
    end

    test "P7-26: the two-step decode replaces an invalid byte and keeps é, both encodings named" do
      decode = lambda do |bytes|
        bytes.b.force_encoding(::Encoding::UTF_8)
          .encode(::Encoding::UTF_8, ::Encoding::UTF_8, invalid: :replace, undef: :replace)
      end

      assert_equal("a�b", decode.call("a\xFFb".b))
      assert_equal("café", decode.call("café".b))
      # 6c's trap: a same-encoding #encode with NO options validates nothing.
      refute_predicate("a\xFFb".b.force_encoding(::Encoding::UTF_8).encode(::Encoding::UTF_8),
                       :valid_encoding?,)
    end

    test "SSE-24/SSE-28: Closeable's latch flips before a raising #release, once" do
      owner = Class.new do
        include Dexpace::Closeable

        attr_reader :releases

        def initialize(owned:)
          @releases = 0
          initialize_closeable(owned: owned)
        end

        private

        def release
          @releases += 1
          raise ::IOError, "rel"
        end
      end
      owning = owner.new(owned: true)

      assert_raises(::IOError) { owning.close }
      assert_nil(owning.close)
      assert_equal(1, owning.releases)
      borrowing = owner.new(owned: false)
      borrowing.close

      assert_predicate(borrowing, :closed?)
      assert_equal(0, borrowing.releases)
    end

    test "SSE-34: pp on a Data consults #pretty_print, never an #inspect override" do
      require "pp"
      inspect_only = Class.new(Data.define(:name)) { def inspect = "SENTINEL" }
      both = Class.new(Data.define(:name)) do
        def inspect = "SENTINEL"
        def pretty_print(printer) = printer.text(inspect)
      end

      assert_match(/#<data /, inspect_only.new(name: :skip).pretty_inspect)
      assert_equal("SENTINEL\n", both.new(name: :skip).pretty_inspect)
    end
  end
end
