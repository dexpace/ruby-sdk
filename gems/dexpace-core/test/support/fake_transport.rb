# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The in-memory fake the roadmap's cross-cutting constraint 4 requires of phases 1 through 7:
# implements only SEAM-11, holds no socket, and observes the cancellation token at the one point a
# real transport would.
#
# It lives in dexpace-core's test tree and is not public API. A published fake would need a YARD
# block, an RBS mirror and a row in the runtime surface manifest, after which changing its shape
# would be a public API change diffed against a release tag (NFR-4) -- a real cost paid forever for
# a convenience. dexpace-conformance is the gem chartered to publish adapter test doubles (§9.3)
# and it is phase 8's. The move was later declined by phase 8a, on the development-dependency cycle
# it would create, so these fakes stay here.
class FakeTransport
  # @return [Array<Array>] one [request, options, cancellation] triple per call
  attr_reader :calls

  def initialize(response: nil, raises: nil, before_return: nil)
    @response = response
    @raises = raises
    @before_return = before_return
    @calls = []
    @mutex = ::Thread::Mutex.new
  end

  def call(request, options, cancellation)
    @mutex.synchronize { @calls << [request, options, cancellation] }
    @before_return&.call
    raise @raises if @raises

    @response
  end
end
