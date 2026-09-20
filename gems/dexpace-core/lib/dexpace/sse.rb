# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "sse/sentinel"

module Dexpace
  # The Server-Sent Events subsystem, chapter 13: the WHATWG line and field state machine
  # (LineReader, Reader), the immutable five-field event value (Event), the resource-owning
  # single-pass streaming facade (Stream) and the typed adapter over a caller-supplied mapper
  # (TypedStream). It owns no reconnection policy, no last-event-id continuity and no per-API
  # sentinel convention (SSE-37, SSE-38); those live in caller-supplied code, and the one
  # extension point is Stream#typed's mapper, whose vocabulary is SKIP and DONE.
  #
  # Nothing here names a Dexpace::Serde constant or requires a serialization feature, and
  # `gates:serde_boundary` scans this file and every file under lib/dexpace/sse/ to keep it so
  # (SSE-37). The three limits below are the module's, beside the module whose limits they are --
  # phase 3a's placement of Dexpace::IO::MAX_MATERIALIZED_BYTES in io.rb, applied unchanged.
  module SSE
    # SSE-19's line cap, as the DEFAULT: 1 MiB. Chosen, not derived. The reference imposes no
    # maximum line size, so this is SSE-19's documented divergence -- the chapter's own sanction
    # is "a port MAY add a configurable cap and reject/truncate oversized lines, documenting the
    # divergence" -- and the port REJECTS, raising LimitExceededError from the pull on which a
    # line crosses the bound, and never truncates (P7-21). Configurable per reader through the
    # `max_line_bytes:` keyword on LineReader.new, Reader.new and the three Stream factories; no
    # configuration key exists for it, because the caller constructs the reader and is therefore
    # the configuration source.
    #
    # This is the bound phase 3a's line-cap finding names: the one drain-style read
    # Dexpace::IO::MAX_MATERIALIZED_BYTES does not guard is #read_line_utf8 (P3-4), and the bound
    # belongs in the layer that knows what a line means. It is a different bound at a different
    # layer, not a second ceiling under 3a's: the SSE machine reads bytes through
    # BufferedSource#getbyte and calls none of the drain methods 3a's ceiling guards, so the two
    # never meet on one operation. 1 MiB matches phase 3b's MAX_BUFFERED_ERROR_BODY_BYTES in
    # magnitude, deliberately -- one order of magnitude for a reader to remember -- and shares no
    # constant with it. #read_line_utf8 itself remains unbounded and, after this phase, has no
    # caller in this repository: IO-14 keeps a lone "\r" as content where SSE-2 makes it terminate
    # a line, so the SSE machine cannot be built on it (P7-20).
    MAX_LINE_BYTES = 1024 * 1024

    # SSE-19's event cap, as the DEFAULT: 8 MiB of raw bytes accumulated into one event block,
    # reset at every dispatch. Chosen, not derived. Appendix C states the surface SSE-19 leaves
    # open as "no maximum line OR EVENT size", and a line cap alone leaves 2^20 one-byte data lines
    # unbounded, so the MAY's inverse is taken over the whole of the subject the requirement
    # names and no further: there is no cap on the number of events in a stream (P7-21). Eight
    # times the line cap, so a legitimate multi-line event carries several large lines; one
    # eighth of Dexpace::IO::MAX_MATERIALIZED_BYTES, so it is visibly beneath 3a's ceiling.
    # Rejected, never truncated; configurable per reader through `max_event_bytes:`.
    MAX_EVENT_BYTES = 8 * 1024 * 1024

    # SSE-11's magnitude cap on the `retry` field: 2^31 - 1 milliseconds, design section 10.18's
    # substituted constant. Ruby's Integers are arbitrary-precision and cannot overflow, so the
    # reference's "maximum representable millisecond magnitude" has no runtime analogue here; the
    # port documents this cap and IGNORES a larger value rather than wrapping, which preserves the
    # requirement's observable behaviour. Written as the literal because Integer#** types as
    # Numeric under the strict Steep target. This is NOT the line cap: SSE-11 is a MUST about the
    # retry field's value, SSE-19 a MAY about line length, and the two caps carry two constants
    # and two checklist rows because they were confused once already.
    MAX_RETRY_MS = 2_147_483_647

    # SSE-34: the mapper outcome that drops the event and advances to the next, never surfacing
    # it to the consumer. Compared by identity, never by value.
    SKIP = Sentinel.send(:new, name: :skip)

    # SSE-34: the mapper outcome that ends the iteration cleanly and closes the stream without
    # yielding a model for the sentinel event itself. Compared by identity, never by value.
    DONE = Sentinel.send(:new, name: :done)
  end
end
