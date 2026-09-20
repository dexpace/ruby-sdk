# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"
require_relative "fake_response_body"
require_relative "scripted_chunked"

# The byte streams and the one stream-building helper every phase-7b SSE suite is written
# against, in the shape of RecoveryFixtures, RetryFixtures, AuthFixtures and RedirectFixtures:
# a top-level module the suites `include`. Every source here is a REAL Dexpace::IO::BufferedSource
# -- the plan's ByteSource, CountingBody, CountingResource, PipeSource and FakeSSEResponse
# doubles were written against stand-ins the tree never had, and the real objects answer every
# assertion the plan wrote for them: `BufferedSource.of_bytes` is a _ByteSource, FakeResponseBody's
# `#closes` counts closes and raises the `close_error:` it is given (SSE-23, SSE-29, SSE-30), a
# ScriptedChunked under `BufferedSource.over` is the mid-stream failure, 3a's FakeChunked is
# SSE-39's yield counter, RecoveryFixtures#build_response is a real Dexpace::Response for SSE-32,
# and `BufferedSource.wrapping` over an `IO.pipe` read end is SSE-31's parked read.
module SSEFixtures
  # Three one-line events; what SSE-27 and SSE-30 read as %w[a b c].
  FIXTURE = "data: a\n\ndata: b\n\ndata: c\n\n".b.freeze

  # A source over the bytes, owning nothing external.
  def byte_source(bytes = FIXTURE)
    Dexpace::IO::BufferedSource.of_bytes(bytes.b)
  end

  # A source that delivers `bytes` and raises `error` from the pull that follows them.
  def failing_source(bytes, error)
    Dexpace::IO::BufferedSource.over(ScriptedChunked.new(bytes.b, error))
  end

  # A close-counting resource whose #close raises `close_error` when one is given.
  def counting_resource(close_error: nil)
    FakeResponseBody.new(nil, close_error: close_error)
  end

  # Drives a block form to completion and answers what it yielded, so a suite exercises the
  # block shape without RuboCop reading `each { |v| out << v }` as a missed #map -- there is
  # no #map on a Stream or a TypedStream, by design (SSE-26).
  def gathered(target)
    out = []
    target.each { |value| out << value } # rubocop:disable Style/MapIntoArray -- the block form has no #map
    out
  end

  # SSE-25's partial consume in the block form: one event, then out of the block.
  def consume_one(stream)
    stream.each { |event| break event } # rubocop:disable Lint/UnreachableLoop -- the break IS the partial consume
  end

  # The one shared helper: `stream_over(bytes = FIXTURE, resource: nil) -> [stream, resource]`,
  # an OWNING stream over a real source and a counting resource. It returns two values at every
  # call site: `stream, resource = stream_over(...)` or `stream, = stream_over(...)`.
  def stream_over(bytes = FIXTURE, resource: nil, **)
    resource ||= counting_resource
    [Dexpace::SSE::Stream.owning(byte_source(bytes), resource: resource, **), resource]
  end
end
