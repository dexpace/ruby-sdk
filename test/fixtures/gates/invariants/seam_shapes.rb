# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Every way core could name a concrete seam implementation, and four constants it legitimately
# owns in the same namespaces.
module Dexpace
  module Bad
    A = Dexpace::Serde::JSON
    B = ::Dexpace::Serde::JSON
    C = Serde::JSON
    D = Object.const_get("Dexpace::Transport::NetHTTP")
    E = Object.const_get(:"Dexpace::Async::Thread")   # a Symbol literal, caught the same way
    F = Dexpace::Serde::JSON::Codec                    # a leaf pair deeper in the path

    OK1 = Dexpace::Registry           # a core constant; must NOT be reported
    OK2 = Dexpace::Serde::Error       # the seam's own error type; must NOT be reported
    OK3 = Async::Future               # core's own async surface; must NOT be reported
    OK4 = Instrumentation::Severity   # core's own instrumentation; must NOT be reported
  end
end
