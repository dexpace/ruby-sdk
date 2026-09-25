# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "ast_scan"

# The repository-wide invariant scans (design R4). Each returns a list of offence strings; the
# Rake task prints them and exits non-zero when the list is non-empty.
#
# These are Rake GATES and not conformance assertions because their subject is THIS repository's
# source tree, which does not exist in a consumer's process. `dexpace-conformance` ships in `lib/`
# so a third party can run it against THEIR gem; a scan of `gems/*/lib/` would be meaningless
# there, and putting it in that gem would make it read a filesystem it does not own.
module InvariantGates
  # XCUT-9: `Dexpace.each_cause` is the single cause walk (4b's hand-forward).
  CAUSE_WALK_ALLOWED = [
    "gems/dexpace-core/lib/dexpace/each_cause.rb", # the single walk itself
  ].freeze

  # SEAM-2, matched by the ADAPTER-OWNED LEAF namespace anywhere in the path. Measured twice
  # during planning: a fixed list of fully qualified names caught 0 of 4 realistic shapes, and
  # matching any path under a SEAM namespace (Serde, Transport, Async, Instrumentation) flagged 31
  # conforming references in 15 of core's own files -- `Async::Completer`, `Async::Future`,
  # `Instrumentation::*` -- because core legitimately owns constants there. So the rule names the
  # LEAF each MVP adapter gem owns (CLAUDE.md's gem table).
  #
  # **Stated gap:** a later adapter gem adds its leaf here or is invisible to this gate.
  ADAPTER_NAMESPACES = [%w[Serde JSON], %w[Transport NetHTTP], %w[Transport AsyncHTTP],
                        %w[Async Thread],].freeze

  # XCUT-14: `Dexpace::BoundedMap` is the one bounded-keyed-map implementation (4a's
  # hand-forward), so its own file is the first exclusion and every other entry is an ADJUDICATED
  # false positive. A path => reason Hash, exactly as phase 0's require allowlist is, because an
  # allowlist whose entries carry no argument is a list of things somebody once silenced.
  #
  # **Adjudicated 2026-09-23 against the tree AS BUILT, not against a filed plan fence.** With an
  # empty allowlist the gate reports nine Hash ivars in nine files; six are here. XCUT-14 scopes
  # itself to a "process/instance-lived map whose key space is influenced by callers or remote
  # servers" and adds that "the cap is a memory backstop and MUST NOT be relied on as the
  # primary cleanup mechanism". What every entry here has in common is that last clause: the
  # map's primary cleanup is its OWNER being dropped after one operation, so a cap could never
  # be the backstop. That property is a LIFETIME, and a lifetime is not decidable from one
  # file -- which is why the allowlist is the mechanism and not a cleverer scan.
  #
  # The planning adjudication named `gems/dexpace-core/lib/dexpace/configuration.rb`, which holds
  # no Hash ivar at all: 5a's two accumulators are in `configuration/builder.rb`. That entry
  # silenced nothing and survived a whole adjudication, which is why the integrity test below
  # asserts that every key still REPORTS at that path rather than only that the file exists.
  BOUNDED_MAP_ALLOWED = {
    "gems/dexpace-core/lib/dexpace/bounded_map.rb" =>
      "@h IS Dexpace::BoundedMap's own store -- the single implementation this gate exists to " \
      "keep single (4a's P4-3)",
    "gems/dexpace-core/lib/dexpace/configuration/builder.rb" =>
      "@overrides and @properties are Configuration::Builder accumulators discarded at #build, " \
      "and the built Configuration is a frozen Data; the keys are the embedder's own CFG keys, " \
      "not caller or server input",
    "gems/dexpace-core/lib/dexpace/instrumentation/event.rb" =>
      "@fields is ONE log event's field bag, allocated per call and dropped at #emit; its " \
      "lifetime is a single operation, so a cap could never be the memory backstop XCUT-14 " \
      "describes. The closest call of the five: http.response.header.* keys ARE " \
      "server-influenced, so it fails the key-space clause and passes on lifetime alone",
    "gems/dexpace-core/lib/dexpace/auth/challenges.rb" =>
      "@params is ONE challenge parse's accumulator inside the private_constant Parser, reset at " \
      "every open_challenge/emit and dropped with the parse -- the same lifetime argument the " \
      "log event carries. The nonce COUNTER, which is caller- and server-keyed, is a real " \
      "BoundedMap in auth/digest_handler.rb",
    "gems/dexpace-conformance/lib/dexpace/conformance/recording_span.rb" =>
      "@attributes is one RecordingSpan double's record, inert after #finish and dropped with " \
      "the span",
    "gems/dexpace-transport-async_http/lib/dexpace/transport/async_http/clients.rb" =>
      "@by_key IS capped, and the scan cannot see a cap. VERIFIED by reading the file on " \
      "2026-09-23: Clients#fetch inserts with ||= and calls #drain inside the SAME " \
      "@mutex.synchronize as the insert, and #drain is a LOOP -- " \
      "`evicted << @by_key.delete(@by_key.keys.first) while @by_key.size > MAX_ORIGINS`, with " \
      "clients whose reactor has closed evicted first -- so a concurrent insert burst converges " \
      "to the bound instead of overshooting permanently, which is XCUT-14's drain clause " \
      "exactly; every evicted client's pool is retired outside the lock. Phase 9's planning " \
      "adjudicated this as the one TRUE positive of six, against 8c's filed plan fence rather " \
      "than its code, and 8c shipped the bound its Task 8 promised. The MECHANISM behind this " \
      "reading (phase 10, 2026-09-25): clients_test.rb's three XCUT-14 cases -- 'the map is " \
      "bounded at MAX_ORIGINS and drains back to the cap after each insert', 'an evicted " \
      "client's pool is retired and closed, never merely dropped' and 'a client whose reactor " \
      "has closed is evicted before a live one' -- go red if the cap, the loop or the close goes",
  }.freeze

  extend self

  # @param files [Array<String>] every file to scan
  # @param allowed [Array<String>] paths whose walk is the single walk itself
  # @return [Array<String>] one offence line per violation
  def cause_walk(files, allowed: CAUSE_WALK_ALLOWED)
    offences(files, allowed) do |path|
      AstScan.receiver_calls(path, [:cause]).map do |(_, line, _)|
        "#{path}:#{line}: walks #cause outside Dexpace.each_cause (XCUT-9)"
      end
    end
  end

  # A Hash assigned to an instance variable is the shape a caller- or server-keyed map takes.
  #
  # @param files [Array<String>] every file to scan
  # @param allowed [Hash{String => String}] path => the reason it is not a caller-keyed map
  # @return [Array<String>] one offence line per violation
  def bounded_map(files, allowed: BOUNDED_MAP_ALLOWED)
    offences(files, allowed.keys) do |path|
      AstScan.hash_ivar_assignments(path).map do |(_, line, ivar)|
        "#{path}:#{line}: #{ivar} is a Hash on an instance; only Dexpace::BoundedMap may hold a " \
          "caller- or server-keyed map (XCUT-14)"
      end
    end
  end

  # @param files [Array<String>] core's own files
  # @param namespaces [Array<Array(String, String)>] each adapter's leaf pair
  # @return [Array<String>] one offence line per violation
  def seam_names(files, namespaces: ADAPTER_NAMESPACES)
    offences(files, []) do |path|
      candidates = AstScan.constant_paths(path) + AstScan.string_literals(path)
      candidates.filter_map do |(_, line, rendered)|
        next unless concrete_seam?(rendered.to_s, namespaces)

        "#{path}:#{line}: core names the concrete seam implementation #{rendered} (SEAM-2)"
      end
    end
  end

  # `Dexpace::Serde::JSON`, `::Dexpace::Serde::JSON`, bare `Serde::JSON` and
  # `Dexpace::Serde::JSON::Codec` all contain an adapter's leaf pair as CONSECUTIVE segments;
  # `Dexpace::Serde::Error`, `Dexpace::Async::Future` and `Instrumentation::Severity` contain
  # none.
  def concrete_seam?(rendered, namespaces)
    rendered.delete_prefix("::").split("::").each_cons(2).any? { |pair| namespaces.include?(pair) }
  end

  def offences(files, allowed, &)
    (files - allowed).flat_map(&)
  end
end
