# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace"

# A response-side body that counts how often it was read and how often it was released.
#
# Dexpace::Body is a MODULE (phase 3b), so this includes it rather than subclassing it, and it
# includes Dexpace::Closeable AFTER it -- the order phase 3b uses everywhere a body is closable --
# so the latch's #close wins over the module's no-op default.
#
# It counts #release and NOT #close, on purpose: two assertions in phase 4b are release COUNTS
# rather than release facts -- RECOV-12's "exactly once" and RECOV-13's "zero" -- and RECOV-12's
# path calls #close twice, once from Body.buffer_bounded's ensure and once from the chain's own
# close, so a fake counting #close would assert 2 where the requirement says once, and would pass
# against a chain that had dropped Closeable's latch. #source is counted for PIPE-37's clause: a
# non-error response passes the error-mapping step with its body not read, consumed or closed.
#
# It lives in dexpace-core's test tree and is not public API, for the reason fake_transport.rb
# states.
class RecordingBody
  include Dexpace::Body
  include Dexpace::Closeable

  attr_reader :release_count, :source_count

  def initialize(content = "body")
    initialize_closeable
    @content = content.b
    @release_count = 0
    @source_count = 0
  end

  def source
    @source_count += 1
    Dexpace::IO::BufferedSource.of_bytes(@content)
  end

  private

  def release
    @release_count += 1
  end
end
