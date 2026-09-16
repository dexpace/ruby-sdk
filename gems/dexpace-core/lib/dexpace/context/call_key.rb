# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"

module Dexpace
  # CTX-4's default key generator: a process-wide, monotonically increasing counter appended to a
  # 'traceId:spanId' rendering, so a key is debuggable by eye (design §5.4 rejects a bare UUID for
  # losing exactly that) and call-unique whatever the prefix is. With Bundle::NONE -- the shared
  # singleton every untraced call carries -- the prefix is constant across the whole process,
  # which is the condition CTX-15's last clause names, and the suffix is what keeps the key unique
  # anyway.
  #
  # Not public API (P4-3): CTX-4 says outright that "the exact format and the counter mechanism
  # are a reference choice, and a port MAY key differently", and NFR-4 locks every public name at
  # the first release tag. The public surface is #call_key on a context, a frozen String. A
  # private_constant on Dexpace is reachable by a bare name from any `module Dexpace; ...` body
  # and from nowhere else (bounded_map.rb, and docs/knowledge/notes/execution-context.md).
  #
  # One Thread::Mutex, one Integer, incremented under the lock and read nowhere else. A counter on
  # a ContextStore instance would mint colliding keys the moment a second store exists, and CTX-6
  # requires distinctness "across the whole process and across all three context flavors", not
  # across a store. The mutex is held across the increment and nothing else, and it stays although
  # CRuby's GVL would hide its absence: 16 threads x 5000 increments lose no update with OR
  # without it on CRuby (design, verified fact 9), which is precisely how an unguarded counter
  # ships and then fails on JRuby or TruffleRuby. Ruby's Integer never overflows, so there is no
  # wrap handling (verified fact 10). The key is frozen with #freeze, never String#-@: a
  # per-call-unique key deduplicates against nothing, so interning pays for an index entry it
  # never reuses (verified fact 11), and a frozen String is stored as a Hash key by identity
  # where an unfrozen one is copied on every registration (verified fact 12).
  module CallKey
    @mutex = ::Thread::Mutex.new
    @counter = 0

    # The bundle is checked here as well as in the flavour's #initialize, because a .build mints
    # before it constructs and an absent bundle must fail with SEAM-29's message, not with a
    # NoMethodError off nil.
    #
    # @param bundle [Instrumentation::Bundle] the bundle whose two identifiers render the prefix
    # @return [String] a frozen, process-unique key of the form "traceId:spanId:n"
    def self.mint(bundle)
      Model.required!("bundle", bundle)
      n = @mutex.synchronize { @counter += 1 }
      "#{bundle.trace_id}:#{bundle.span_id}:#{n}".freeze
    end
  end
  private_constant :CallKey
end
