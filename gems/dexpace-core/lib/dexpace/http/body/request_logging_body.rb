# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../../io/tee_sink"

module Dexpace
  # BODY-17..BODY-21 and BODY-37: the tee-on-write capture wrapper.
  #
  # Nothing in core constructs one of these. That is how BODY-34's enablement clause ("body
  # logging MUST be engaged only when body-level logging is enabled") is satisfied in phase 3b --
  # STRUCTURALLY, not by a flag: the wrapper is off the path unless something builds it, and the
  # only thing that will is phase 5's instrumentation layer (phase 5b, Tasks 14-15).
  class RequestLoggingBody
    include Dexpace::Body

    # BODY-19 states this default in its own text: "The unbounded default cap exists for direct
    # wrapper use; the instrumentation layer always supplies a finite cap." 3a's TeeSink already
    # implements exactly that and this passes the value through.
    #
    # DELIBERATELY ASYMMETRIC with ResponseLoggingBody, which REQUIRES its cap (P3-18). Unifying the
    # two defaults breaks one requirement or the other. The cap is validated here, at construction,
    # rather than at the first write, so a caller's mistake is reported where it was made; the
    # rule is the tee's own -- a non-negative Integer, or Float::INFINITY for unbounded.
    def initialize(delegate, tap_limit: ::Float::INFINITY)
      unless delegate.respond_to?(:write_to)
        raise Dexpace::InvalidArgumentError,
              "a request-logging wrapper takes a body responding to #write_to, " \
              "got #{delegate.class}"
      end

      @delegate = delegate
      @tap_limit = validated_tap_limit(tap_limit)
      @tee = nil
    end

    # The wrapped body.
    attr_reader :delegate

    # The delegate's: a tee changes no header-visible fact about the body.
    def media_type
      @delegate.media_type
    end

    # The delegate's, verbatim: the full payload reaches the wire whatever the tap cap.
    def content_length
      @delegate.content_length
    end

    # BODY-21: the delegate's replayability, VERBATIM.
    def replayable?
      @delegate.replayable?
    end

    # BODY-21: a wrapper around the delegate's replayable form, with the tap cap preserved, so a
    # retry loop keeps capturing bytes for every attempt. BODY-3's "return the same body unchanged
    # when already replayable" wins when it applies, which is the same object either requirement
    # would name.
    def to_replayable
      return self if replayable?

      self.class.new(@delegate.to_replayable, tap_limit: @tap_limit)
    end

    # BODY-17: the tee mirrors the exact bytes the delegate's single write produces while forwarding
    # those same bytes to `sink`, consuming the upstream exactly once, and the FULL untruncated
    # payload reaches `sink` whatever the cap (IO-25/IO-26).
    #
    # A FRESH tee per write, which is BODY-18 satisfied by construction and strictly stronger than
    # clearing one: it also drops the previous attempt's memory. It is why 3a shipped TeeSink
    # without #clear_tap (3a's checklist, deviation 1).
    #
    # The wrapper never calls #close, #flush or #emit on the tee: IO-29 forwards all three to the
    # PRIMARY, and the primary is the transport's sink, which a body does not own (BODY-8, §10.12).
    def write_to(sink)
      tee = Dexpace::IO::TeeSink.new(primary: sink, tap_limit: @tap_limit)
      @tee = tee
      @delegate.write_to(tee)
    end

    # BODY-20: a write that failed partway still returns the bytes mirrored up to the failure,
    # because @tee is bound before the delegate runs and IO-27 makes the tee mirror BEFORE it
    # forwards. Empty BINARY before the first write.
    def snapshot
      tee = @tee
      tee.nil? ? (+"").b : tee.tap_snapshot
    end

    # How many bytes the tap of the most recent write holds -- at most the cap.
    def tap_bytesize
      tee = @tee
      tee.nil? ? 0 : tee.tap_bytesize
    end

    # HTTP-46, and BODY-37's shape: a wrapper is equal to a wrapper over an equal delegate with the
    # same cap. The wrapper exposes no buffer handle of its own -- BODY-37 is IO-28 restated at this
    # layer and is ONE mechanism, not two; TeeSink#buffer already raises with the actionable
    # message, and design §10.10 records the honest position that the prohibition cannot be
    # language-enforced.
    def ==(other)
      other.is_a?(RequestLoggingBody) && other.delegate == @delegate &&
        other.send(:tap_limit) == @tap_limit
    end
    alias eql? ==

    # Agrees with #==.
    def hash
      [self.class, @delegate, @tap_limit].hash
    end

    private

    # Reached with `send` from #==, as phase 1's Headers#== reaches #values.
    attr_reader :tap_limit

    # The tee's own rule, applied at construction: nil and Float::INFINITY both spell unbounded,
    # and are stored as the latter so two unbounded wrappers compare equal.
    def validated_tap_limit(limit)
      return ::Float::INFINITY if limit.nil? || limit == ::Float::INFINITY
      return limit if limit.is_a?(::Integer) && !limit.negative?

      raise Dexpace::InvalidArgumentError,
            "tap_limit must be a non-negative Integer or Float::INFINITY, got #{limit.inspect}"
    end
  end
end
