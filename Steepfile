# frozen_string_literal: true
# SPDX-License-Identifier: MIT

D = Steep::Diagnostic

# NFR-3, and docs/knowledge/notes/type-system.md. Six targets from day one rather than one
# repository-wide target, because "target-by-target" is only a real discipline if the targets
# exist before anyone needs to relax one. Every future relaxation is a change to a named target
# with a comment, never a blanket ignore.
target :core do
  check "gems/dexpace-core/lib"
  signature "gems/dexpace-core/sig"
  # The stdlib signature sets for the names RequireAllowlist::ALLOWED admits -- all but `set`,
  # which rbs 4 ships under core/ rather than stdlib/ (Set is a core class from Ruby 4.0), so
  # naming it here is an UnknownLibraryError.
  library "uri", "stringio", "strscan", "time", "date", "digest", "securerandom", "monitor",
          "forwardable", "singleton", "openssl"

  # Core's public surface is strict. This is the one target that never relaxes.
  configure_code_diagnostics(D::Ruby.strict)
end

target :net_http do
  check "gems/dexpace-transport-net_http/lib"
  signature "gems/dexpace-transport-net_http/sig", "gems/dexpace-core/sig"
  # `net-http` here is rbs's own stdlib signature set, not a gem dependency: the adapter
  # declares none until phase 8.
  library "net-http", "uri"
  configure_code_diagnostics(D::Ruby.default)
end

target :async_http do
  check "gems/dexpace-transport-async_http/lib"
  signature "gems/dexpace-transport-async_http/sig", "gems/dexpace-core/sig"
  # rbs's own stdlib signature sets for the two features this gem's lib/ names beyond core's
  # allowlist: `openssl` for the default TLS context and `uri` for the request URL.
  library "openssl", "uri"
  # The second relaxation, on this target alone (phase 8c), for the same reason as
  # :serde_json's: none of async, async-http, protocol-http or async-pool ships a sig/ and the
  # collection carries none, so every `::Async::HTTP::Client.new`, `::Protocol::HTTP::Request.new`
  # and the `< ::Protocol::HTTP::Body::Readable` superclass is a Ruby::UnknownConstant that
  # steep's default warning severity turns into a red gate. Downgraded to :information here,
  # never a line-level ignore and never on core's strict target; every handle on the runtime is
  # typed `untyped` in the gem's sig (NFR-11 admits no async-family type there either).
  # Re-tighten to D::Ruby.default at the first release of those gems, or of the collection, that
  # declares them.
  configure_code_diagnostics(D::Ruby.default.merge({ D::Ruby::UnknownConstant => :information }))
end

target :serde_json do
  check "gems/dexpace-serde-json/lib"
  signature "gems/dexpace-serde-json/sig", "gems/dexpace-core/sig"
  library "json"
  # The one relaxation, on this target alone (phase 7a): rbs 4.2.0's stdlib json signatures
  # declare JSONError, GeneratorError, ParserError, State, generate and parse -- and no
  # `JSON::Coder`, the per-instance engine json 2.19.9 added and this adapter is built on -- while
  # json 3.0.2 ships no sig/ of its own for `rbs collection` to pick up. So the codec's one
  # `::JSON::Coder.new` is a Ruby::UnknownConstant that steep's default warning severity turns
  # into a red gate. Downgraded to :information here, never a line-level ignore (no precedent in
  # lib/) and never on core's strict target; the engine is typed `untyped` in the gem's sig
  # (NFR-11 admits no `::JSON` type there either). Re-tighten to D::Ruby.default at the first rbs
  # release that declares JSON::Coder.
  configure_code_diagnostics(D::Ruby.default.merge({ D::Ruby::UnknownConstant => :information }))
end

target :async_thread do
  check "gems/dexpace-async-thread/lib"
  signature "gems/dexpace-async-thread/sig", "gems/dexpace-core/sig"
  configure_code_diagnostics(D::Ruby.default)
end

target :conformance do
  check "gems/dexpace-conformance/lib"
  signature "gems/dexpace-conformance/sig", "gems/dexpace-core/sig"
  # rbs's own stdlib signature sets for the two features this gem's lib/ requires beyond core's
  # allowlist: `socket` for the wire fixture (P8-14) and `tempfile` for TRANSPORT-28's file body.
  library "socket", "tempfile"
  configure_code_diagnostics(D::Ruby.default)
end
