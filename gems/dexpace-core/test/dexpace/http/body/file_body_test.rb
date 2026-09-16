# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../../test_helper"
require "dexpace"
require_relative "../../../support/fake_sink"
require "tempfile"

# HTTP-40, HTTP-46, BODY-1, BODY-11, BODY-12, BODY-13, and §7.1's residue.
#
# One class per behaviour group, because Metrics/ClassLength caps a class at 100 lines: BODY-11's
# construction clauses here, then Window, Handles, Residue and Equality below.
class DexpaceFileBodyTest < DexpaceTestCase
  # One shared fixture set for every class below.
  module Files
    def with_file(content = "0123456789")
      ::Tempfile.create("file_body") do |file|
        file.binmode
        file.write(content)
        file.flush
        yield file
      end
    end

    def drain(body)
      sink = Dexpace::IO::Buffer.new
      body.write_to(sink)
      sink.snapshot
    end
  end
  include Files

  # A FileBody-shaped double: a resource acquired and released inside an ordinary #each method,
  # which is exactly the shape BODY-11's fresh-handle-per-write requirement forces.
  class LeakyEach
    attr_reader :events, :saw_block

    def initialize
      @events = []
      @saw_block = nil
    end

    def each
      @saw_block = block_given?
      @events << :open
      begin
        yield "a"
        yield "b"
        yield "c"
      ensure
        @events << :close
      end
    end
  end

  # ---- BODY-11's six construction clauses, one test each -----------------------------------
  # A single "it validates" test would pass with five of the six checks missing, which is why
  # BODY-11 gets six rows here and not one.

  test "rejects a path that does not exist" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Body.file("/nonexistent/dexpace/file")
    end

    assert_includes(error.message, "does not exist")
  end

  test "rejects a directory" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.file(Dir.tmpdir) }

    assert_includes(error.message, "not a regular file")
  end

  test "rejects a character device" do
    skip("no null device on this platform") unless ::File.exist?(::File::NULL)
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.file(::File::NULL) }

    assert_includes(error.message, "not a regular file")
  end

  test "rejects a negative offset" do
    with_file do |file|
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.file(file.path, offset: -1)
      end

      assert_includes(error.message, "offset")
    end
  end

  test "rejects an offset past the size captured at construction" do
    with_file do |file|
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.file(file.path, offset: 11)
      end

      assert_includes(error.message, "past the end")
    end
  end

  test "rejects a count that runs past the size captured at construction" do
    with_file do |file|
      error = assert_raises(Dexpace::InvalidArgumentError) do
        Dexpace::Body.file(file.path, offset: 8, count: 5)
      end

      assert_includes(error.message, "exceeds")
    end
  end

  test "rejects a negative count" do
    with_file do |file|
      assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.file(file.path, count: -2) }
    end
  end

  test "rejects a nil path with SEAM-29's one message form" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Body.file(nil) }

    assert_equal("path is required", error.message)
  end

  # The window, the exact byte count, and BODY-12's clause 2 from this side.
  class WindowTest < DexpaceTestCase
    include Files

    test "resolves a nil count to the rest of the file, so #count is always exact" do
      with_file { |file| assert_equal(10, Dexpace::Body.file(file.path).count) }
    end

    test "writes exactly the offset+count window and nothing outside it" do
      with_file do |file|
        assert_equal("3456".b, drain(Dexpace::Body.file(file.path, offset: 3, count: 4)))
      end
    end

    test "an offset at exactly the size is an empty window, not an error" do
      with_file do |file|
        assert_equal(0, Dexpace::Body.file(file.path, offset: 10).count)
      end
    end

    test "an empty window is a legitimate empty write" do
      with_file do |file|
        sink = FakeSink.new

        assert_equal(0, Dexpace::Body.file(file.path, count: 0).write_to(sink))
        assert_empty(sink.writes)
      end
    end

    test "delivers BINARY bytes" do
      with_file("héllo") do |file|
        assert_equal(::Encoding::BINARY, drain(Dexpace::Body.file(file.path)).encoding)
      end
    end

    test "reports the window as its content length" do
      with_file do |file|
        assert_equal(4, Dexpace::Body.file(file.path, offset: 3, count: 4).content_length)
      end
    end

    # Verified on 3.2.11, 3.4.10 and 4.0.6: ::IO.copy_stream checks respond_to?(:to_path) first,
    # and copy_stream(body, sink) with no length then copies the WHOLE FILE. Defining #to_path would
    # make a transport doing the obvious thing silently upload every byte and ignore the window.
    test "does not define #to_path, which would make a transport ignore the window" do
      with_file do |file|
        body = Dexpace::Body.file(file.path, offset: 3, count: 4)

        refute_respond_to(body, :to_path)
      end
    end

    test "exposes path, offset and count instead, which is what a transport dispatches on" do
      with_file do |file|
        body = Dexpace::Body.file(file.path, offset: 3, count: 4)

        assert_respond_to(body, :path)
        assert_respond_to(body, :offset)
        assert_respond_to(body, :count)
        assert_equal([file.path, 3, 4], [body.path, body.offset, body.count])
      end
    end
  end

  # BODY-11's fresh handle per write, and BODY-13's short write.
  class HandlesTest < DexpaceTestCase
    include Files

    test "is replayable and writes identical bytes on every write" do
      with_file do |file|
        body = Dexpace::Body.file(file.path, offset: 3, count: 4)

        assert_predicate(body, :replayable?)
        assert_equal("3456".b, drain(body))
        assert_equal("3456".b, drain(body))
      end
    end

    test "opens a fresh handle per write, so concurrent writes do not share a cursor" do
      with_file("0123456789" * 64) do |file|
        body = Dexpace::Body.file(file.path)
        results = ::Thread::Queue.new
        threads = Array.new(8) { ::Thread.new { results << drain(body) } }
        threads.each(&:join)
        collected = Array.new(8) { results.pop }

        assert_equal([("0123456789" * 64).b], collected.uniq)
      end
    end

    test "does not disturb a caller's own open handle, because it opens its own" do
      with_file do |file|
        file.rewind
        file.read(4)
        drain(Dexpace::Body.file(file.path, offset: 0, count: 10))

        assert_equal(4, file.pos)
      end
    end

    test "detects a short write and names transferred-of-total" do
      with_file do |file|
        body = Dexpace::Body.file(file.path, count: 10)
        error = assert_raises(Dexpace::StreamError) { body.write_to(FakeSink.new(3)) }

        assert_includes(error.message, "3")
        assert_includes(error.message, "10")
      end
    end

    # A file that shrank after construction ends early: the window was captured then, and a
    # short transfer is BODY-13's error, never a silently truncated body.
    test "a file truncated after construction raises rather than sending a short body" do
      with_file do |file|
        body = Dexpace::Body.file(file.path, count: 10)
        file.truncate(4)
        error = assert_raises(Dexpace::StreamError) { drain(body) }

        assert_includes(error.message, "4")
        assert_includes(error.message, "10")
      end
    end

    # Counted through /proc rather than ObjectSpace, which design §7.1 and
    # `resource-management/1676974d` bar twice over: an ObjectSpace sweep answers "has the collector
    # got to it yet", which is precisely the question a deterministic-cleanup test must not ask.
    test "closes its handle even when the sink raises partway" do
      skip("descriptor counting needs /proc") unless ::File.directory?("/proc/self/fd")
      with_file do |file|
        body = Dexpace::Body.file(file.path)
        before = ::Dir.children("/proc/self/fd").length

        20.times do
          assert_raises(Dexpace::StreamError) do
            body.write_to(FakeSink.new(Dexpace::StreamError.new("boom")))
          end
        end

        assert_equal(before, ::Dir.children("/proc/self/fd").length)
      end
    end

    # ::IO.copy_stream reuses and CLEARS one destination String across #write calls, so a BlockSink
    # that yielded its argument would hand every consumer a buffer that is empty the instant the
    # block returns -- `file_body.each.to_a` as N zero-length Strings, all the same object (verified
    # on 3.2.11, 3.4.10 and 4.0.6). FileBody is the one variant whose bytes never pass through
    # #emit_exactly, so it is the only place this can be asserted.
    test "each yields independent chunks that survive the block, over a real copy_stream write" do
      with_file("\xC3\xA9".b * 60_000) do |file|
        chunks = Dexpace::FileBody.new(file.path).each.to_a

        assert_equal(120_000, chunks.sum(&:bytesize))
        assert(chunks.none?(&:empty?))
        assert(chunks.all? { |chunk| chunk.encoding == ::Encoding::BINARY })
      end
    end
  end

  # §7.1's residue: the three verified behaviours, asserted rather than described.
  class ResidueTest < DexpaceTestCase
    test "internal iteration with a break runs the ensure" do
      log = LeakyEach.new
      log.each { |chunk| break if chunk == "b" }

      assert_includes(log.events, :close)
    end

    test "a full external drive to StopIteration runs the ensure" do
      log = LeakyEach.new
      enumerator = log.to_enum(:each)
      begin
        loop { enumerator.next }
      rescue ::StopIteration
        nil
      end

      assert_includes(log.events, :close)
    end

    # The residue itself, stated as a fact rather than as a claim that it is prevented. There is
    # no ObjectSpace finalizer here on purpose: `resource-management/1676974d` and design §7.1 both
    # bar relying on the collector for deterministic cleanup.
    test "next-then-abandon does not run the ensure, and neither does rewind" do
      abandoned = LeakyEach.new
      enumerator = abandoned.to_enum(:each)
      enumerator.next
      enumerator = nil # rubocop:disable Lint/UselessAssignment -- dropping the reference IS the test
      ::GC.start
      ::GC.start

      rewound = LeakyEach.new
      rewind_enumerator = rewound.to_enum(:each)
      rewind_enumerator.next
      rewind_enumerator.rewind

      refute_includes(abandoned.events, :close)
      refute_includes(rewound.events, :close)
    end

    # block_given? is TRUE inside #each when the method is reached through to_enum(:each), so a
    # `raise unless block_given?` guard forbids nothing. The defence is where the resource lives,
    # and for FileBody there is nowhere for it to live.
    test "block_given? is true under external iteration, so no in-method guard can help" do
      probe = LeakyEach.new
      probe.to_enum(:each).next

      assert(probe.saw_block)
    end

    test "FileBody's own documentation states the residue rather than claiming it is closed" do
      path = File.expand_path("../../../../lib/dexpace/http/body/file_body.rb", __dir__)
      source = File.read(path)

      assert_includes(source, "to_enum(:each)")
      assert_includes(source, "LEAKS")
    end
  end

  # HTTP-46.
  class EqualityTest < DexpaceTestCase
    include Files

    test "compares by value over path, offset, count and media type" do
      with_file do |file|
        assert_equal(Dexpace::Body.file(file.path, offset: 1, count: 2),
                     Dexpace::Body.file(file.path, offset: 1, count: 2),)
        refute_equal(Dexpace::Body.file(file.path, offset: 1, count: 2),
                     Dexpace::Body.file(file.path, offset: 2, count: 2),)
        assert_equal(Dexpace::Body.file(file.path).hash, Dexpace::Body.file(file.path).hash)
      end
    end

    test "is frozen, and has no readable source, because it is a request body" do
      with_file do |file|
        body = Dexpace::Body.file(file.path)

        assert_predicate(body, :frozen?)
        assert_raises(Dexpace::StreamError) { body.source }
      end
    end
  end
end
