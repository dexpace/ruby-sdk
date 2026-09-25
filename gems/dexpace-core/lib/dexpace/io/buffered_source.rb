# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "typed_reads"
require_relative "../closeable"
require_relative "../error/invalid_argument_error"
require_relative "../error/closed_error"

module Dexpace
  module IO
    # The reader: IO-6, IO-11..IO-24, IO-41, IO-42. Also, per design §10.2, a canonical body
    # representation, because it responds to #each yielding BINARY chunks.
    #
    # Ownership is two frozen construction-time facts, never a close-time judgement. Closeable's
    # `@owned` is always true -- a source always owns its own buffer -- and a separate frozen
    # `@dexpace_owns_upstream` decides whether #release also closes the upstream. The factory names
    # carry it: .wrapping owns (IO-6), .of_bytes and .over own nothing. IO-6 is read out of
    # appendix C, and cited with design §10.12; SEAM-3, which the older statements of the rule
    # cite, is retired (docs/knowledge/notes/message-bodies.md).
    class BufferedSource # rubocop:disable Metrics/ClassLength -- three factories, three fill paths, one class; see above
      include Dexpace::IO::TypedReads
      include Dexpace::Closeable

      # The three facts that make a source a VIEW, folded into one value: the object it reads
      # through, the absolute position in that object's byte stream where its window starts, and
      # how wide that window is. One argument rather than three keeps #initialize inside
      # Metrics/ParameterLists' budget of four and makes "is this a view?" one nil check. A Data
      # instance is frozen on construction, which is exactly what a construction-time fact wants.
      # private_constant, so it is not NFR-4 surface and the runtime snapshot's constant walk,
      # which skips private constants, never sees it.
      View = ::Data.define(:parent, :pin, :window)

      private_constant :View

      private_class_method :new

      # IO-6: the returned wrapper TAKES OWNERSHIP -- closing it closes `io`. There is deliberately
      # no borrowing variant, because a wrapper that did not close what it wrapped is the exact
      # object IO-6 prohibits (P3-12).
      #
      # `io` is anything responding to #readpartial or #read. Checked with respond_to?, never
      # is_a?(IO): a nominal test would be silently false inside `module Dexpace`, and the duck
      # test is what makes a StringIO, an IO.pipe end, a Tempfile and a caller's own
      # #readpartial-shaped object all work.
      #
      # With a block, closes on any exit path and returns the block's value
      # (`resource-management/bf5560dc`); without one the caller owns the close.
      def self.wrapping(io)
        unless io.respond_to?(:readpartial) || io.respond_to?(:read)
          raise Dexpace::InvalidArgumentError,
                "a wrapped stream must respond to #readpartial or #read, got #{io.class}"
        end

        source = new(upstream: io, owns_upstream: true)
        return source unless block_given?

        begin
          yield source
        ensure
          source.close
        end
      end

      # An INDEPENDENT copy of the input, so a later mutation of the caller's String does not
      # change the source and vice versa (IO-30's surviving behavioural clause, kept even though
      # the ID is a permanent simplification). Owns no external resource -- IO-6's last sentence.
      #
      # The copy is taken here, frozen, and handed on as a ONE-CHUNK #each-shaped body, because a
      # byte array already IS a canonical body representation (§10.2). That leaves one buffered
      # construction path instead of two to keep in step, and #store_append keeps an
      # already-frozen BINARY chunk without copying it a second time.
      def self.of_bytes(string)
        unless string.is_a?(::String)
          raise Dexpace::InvalidArgumentError, "of_bytes takes a String, got #{string.class}"
        end

        new(chunked: [string.b.freeze].freeze)
      end

      # Design §3.1's single inverse adapter over §10.2's duck type: any object responding to
      # #each and yielding String chunks. It pulls on demand so no read-ahead accumulates, and it
      # OWNS NOTHING -- closing the returned source never calls #close on what it wrapped, because
      # its callers are always downstream of something that already owns the response (R3,
      # `message-bodies/f060d944`).
      #
      # §7.1's residue, documented rather than papered over: a source closed before exhaustion
      # abandons the enumerator this drives, and an abandoned Enumerator never runs its ensure
      # (verified on 3.2.11, 3.4.10 and 4.0.6; #rewind does not run it either). A #each-shaped
      # object that holds a resource must expose #close and be closed by its owner, because .over
      # will not.
      def self.over(chunked)
        unless chunked.respond_to?(:each)
          raise Dexpace::InvalidArgumentError,
                "over takes an object responding to #each, got #{chunked.class}"
        end

        new(chunked: chunked)
      end

      # The view constructor #peek and #slice reach. Internal, and kept so: a view is a
      # BufferedSource in view mode, which makes IO-23's slice-of-a-slice free and adds no
      # NFR-4-locked constant. It is a private class method with a private RBS declaration, so it
      # sits in neither the surface manifest nor the sig diff; its one caller,
      # TypedReads#build_view, lives outside this class and reaches it through #send, as
      # Headers#== reaches #values -- the hole design §4's P8 records, used from inside core
      # rather than opened as a door.
      def self.__dexpace_view(parent:, pin:, window:)
        new(view: View.new(parent: parent, pin: pin, window: window))
      end

      private_class_method :__dexpace_view

      def initialize(upstream: nil, owns_upstream: false, chunked: nil, view: nil)
        @dexpace_upstream = upstream
        @dexpace_owns_upstream = owns_upstream
        @dexpace_enumerator = chunked&.to_enum(:each)
        @dexpace_view = view
        @dexpace_pulled = 0
        @dexpace_upstream_exhausted = upstream.nil? && chunked.nil? && view.nil?
        initialize_closeable(owned: true)
        initialize_typed_reads
        freeze_construction_facts
      end

      # IO-19/IO-20: true when this source is a non-consuming view over another.
      def view?
        !@dexpace_view.nil?
      end

      # IO-6: whether #close also closes the stream this source wraps.
      def owns_upstream?
        @dexpace_owns_upstream
      end

      protected

      def dexpace_remaining_window
        window = @dexpace_view&.window
        return nil if window.nil?

        [window - dexpace_consumed, 0].max
      end

      private

      # Both construction-time facts are frozen the moment they exist -- a boolean is, and a Data
      # instance is frozen on construction -- so this asserts rather than achieves. It is here
      # because the whole ownership and view story rests on neither ever changing after
      # #initialize returns, and an assertion is what a later reader can check.
      def freeze_construction_facts
        @dexpace_owns_upstream.freeze
        @dexpace_view.freeze
        nil
      end

      # The IO-1/IO-16 EOF sentinels are normalised HERE and nowhere else: readpartial's EOFError
      # and read's nil become one @dexpace_upstream_exhausted flag, which short-circuits every
      # later call. So the rescue runs at most once per stream rather than once per read, and the
      # hot path -- "the bytes are already buffered" -- never enters this method at all.
      def fill(min_bytes)
        return 0 if @dexpace_upstream_exhausted

        view = @dexpace_view
        return fill_from_parent(view, min_bytes) unless view.nil?

        enumerator = @dexpace_enumerator
        return fill_from_enumerator(enumerator) unless enumerator.nil?

        fill_from_upstream(min_bytes)
      end

      # On this path a zero-length return IS exhaustion, and that is a decision: ::IO#read(n),
      # StringIO#read(n), ::IO#readpartial(n) and StringIO#readpartial(n) never return "" for a
      # positive n on 3.2.11, 3.4.10 or 4.0.6 -- they return nil or raise -- so "" is unreachable
      # for every reader Net::HTTP or a test will hand this, and a caller's own object that
      # returns "" forever would spin if it were retried instead (IO-17's zero-read clause, seen
      # from the other side of the contract).
      def fill_from_upstream(min_bytes)
        want = [min_bytes, 1].max
        chunk = pull_from_upstream(want)
        if chunk.nil? || chunk.empty?
          @dexpace_upstream_exhausted = true
          return 0
        end
        store_append(chunk)
      end

      def pull_from_upstream(want)
        upstream = @dexpace_upstream
        return upstream.read(want) unless upstream.respond_to?(:readpartial)

        upstream.readpartial(want)
      rescue ::EOFError
        nil
      end

      # StopIteration is the ONLY end-of-stream signal on this path, so a fill that adds no bytes
      # is retried rather than latched. #each yielding "" is ordinary -- Rack permits it and
      # ["ab", "", "cd"].each is the shortest example -- and a zero-length chunk means "no bytes
      # this time", never "no bytes ever". Collapsing the two truncates a body at its first empty
      # chunk, silently and with a well-formed short read, and violates IO-1's "at least 1 when
      # byteCount>0 and the source is not exhausted".
      def fill_from_enumerator(enumerator)
        added = 0
        added = store_append(enumerator.next) while added.zero?
        added
      rescue ::StopIteration
        @dexpace_upstream_exhausted = true
        0
      end

      # P3-5, which the specification does not state and 3a therefore does. A view pins the
      # parent's cursor at construction and reads a window relative to that pin, driving the
      # parent's #fill without advancing the parent's cursor. If the parent consumes past the
      # window, the view's later reads fail loudly rather than returning bytes from somewhere
      # else -- IO-22's "never returning stale or arbitrary bytes" is the anchor.
      #
      # One fill, like the root's: the parent fills until it holds a byte past `behind` or is
      # done, and this view takes what is there up to `want`. Asking the parent to buffer
      # `behind + want` instead would block a view's #read_into, #readpartial and #each until the
      # whole count arrived, which a root never does (review round 0, R0-1).
      def fill_from_parent(view, min_bytes)
        want = window_budget(view, min_bytes)
        return 0 if want.zero?

        parent = view.parent
        behind = offset_into_parent(view, parent)
        available = parent.dexpace_fill_beyond(behind, want) - behind
        return 0 if available <= 0

        take = [available, want].min
        @dexpace_pulled += take
        # The window copy is fresh and this view owns it, so it is frozen here rather than inside
        # #store_append -- which keeps "at most one copy on the fill path" true on this path too.
        store_append(parent.dexpace_window_copy(behind, take).freeze)
      end

      # How many bytes this fill may pull: at least one, at most `min_bytes`, and never past the
      # window when there is one (a nil window is a peek's, unbounded). Zero once the window is
      # spent, which the caller reads as end of window.
      def window_budget(view, min_bytes)
        want = [min_bytes, 1].max
        window = view.window
        return want if window.nil?

        (window - @dexpace_pulled).clamp(0, want)
      end

      # How far ahead of the parent's own cursor this view's next byte sits -- and P3-5's loud
      # failure when that number goes negative. The parent holds nothing back for a view, so a
      # byte its cursor has already passed cannot be served from anywhere, and IO-22 forbids
      # serving it from somewhere else.
      def offset_into_parent(view, parent)
        behind = view.pin + @dexpace_pulled - parent.dexpace_consumed
        return behind unless behind.negative?

        raise Dexpace::ClosedError,
              "this view's window starts #{-behind} bytes behind the source's cursor: the " \
              "source was read past the pin this view was taken at"
      end

      # IO-22/IO-41/IO-42. The latch has already flipped; this runs exactly once. Drop the buffer,
      # release this view's registration with its parent, invalidate every view derived from THIS
      # source, then close the upstream only if this source owns it.
      def release
        @dexpace_chunks.clear
        @dexpace_head = 0
        @dexpace_buffered = 0
        @dexpace_view&.parent&.dexpace_forget_view(self)
        dexpace_release_views
        upstream = @dexpace_upstream
        upstream.close if @dexpace_owns_upstream && upstream.respond_to?(:close)
        nil
      end
    end
  end
end
