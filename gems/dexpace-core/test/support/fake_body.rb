# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# A Dexpace::Body includer with a scriptable #write_to, and the only deterministic route to
# BODY-20's "the snapshot returns the bytes mirrored up to the failure": a real body either
# succeeds or fails for a reason the test cannot place a byte boundary on.
#
# `chunks` are yielded to the sink in order; `fail_after` is the number of chunks to write before
# raising `error`. It records the sink it was handed, which is how BODY-17's "consuming the
# upstream exactly once" is asserted.
#
# It also answers #source -- P3-23's read side -- as one memoised Dexpace::IO::BufferedSource over
# the joined chunks, so the same double can stand in the slot Body.buffer_bounded drains through.
# `sources` counts how many times the source was built, which is "drained at most once" made
# countable.
class FakeBody
  include Dexpace::Body

  attr_reader :media_type, :content_length, :writes, :sinks, :sources

  OPTIONS = %i[media_type content_length replayable fail_after].freeze

  # **options rather than four keywords beside the splat, because Metrics/ParameterLists caps a
  # signature at four and a test double is not where that budget is spent. The unknown-key check
  # is what keeps a mistyped option a loud failure rather than a silently ignored one.
  def initialize(*chunks, **options)
    unknown = options.keys - OPTIONS
    raise ::ArgumentError, "unknown option(s): #{unknown.join(", ")}" unless unknown.empty?

    @chunks = chunks
    @media_type = options[:media_type]
    @content_length = options.fetch(:content_length, -1)
    @replayable = options.fetch(:replayable, false)
    @fail_after = options[:fail_after]
    @error = Dexpace::StreamError.new("scripted failure")
    @writes = 0
    @sinks = []
    @sources = 0
    @source = nil
  end

  def replayable? = @replayable

  def write_to(sink)
    @writes += 1
    @sinks << sink
    written = 0
    @chunks.each_with_index do |chunk, index|
      raise @error if !@fail_after.nil? && index >= @fail_after

      written += sink.write(chunk.b)
    end
    written
  end

  def source
    if @source.nil?
      @sources += 1
      @source = Dexpace::IO::BufferedSource.of_bytes(@chunks.join.b)
    end
    @source
  end
end
