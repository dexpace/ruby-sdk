# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"

module Dexpace
  # The one bounded-keyed-map implementation XCUT-14's general rule, CTX-11's context store and
  # (phase 6) AUTH-19's per-nonce counter store all share -- design §5.4's "one implementation",
  # as a class rather than a module function because XCUT-14's auditable unit is the map, and a
  # `drain!(hash, cap:)` would leave each consumer to own the hash, the mutex and the decision to
  # call it, which is precisely the drift the shared implementation exists to prevent.
  #
  # Not public API (P4-3): nothing outside this repository's own namespace needs the map, and
  # NFR-4 locks every public name at the first release tag. A private_constant on Dexpace is
  # reachable by a BARE name from any `module Dexpace; module X` body at any nesting depth, in
  # any gem -- the reachability is lexical and per file, and a gem boundary is not a lexical one
  # -- and from nowhere else: the compact `module Dexpace::X` form raises NameError, and so does a
  # qualified `Dexpace::BoundedMap` even from inside Dexpace. Verified on 3.2.11, 3.4.10 and
  # 4.0.6; docs/knowledge/notes/execution-context.md records the condition so phase 6 and phase 9
  # meet it as a stated rule rather than as a NameError.
  #
  # Insert and drain sit in ONE Thread::Mutex#synchronize, so the drain body runs AT MOST ONCE per
  # insert: exactly one key is added per critical section and the loop's invariant on entry is
  # size <= cap, so size <= cap + 1 at the top. It is written as a loop because XCUT-14 makes that
  # a MUST ("using a loop (not a single pre-insert check-then-evict)"), not because a second
  # iteration is reachable under this lock discipline -- and the inverse inference is the trap:
  # the loop does not make the mutex removable. See the corpus note above. The mutex is held
  # across the hash write and the drain of this map's own hash and nothing else; the map never
  # yields to caller code while holding it (concurrency-and-async/f414b864, /c0fab747). Phase 6's
  # #update(key) { |old| new } for AUTH-19's counter increment runs its block under the mutex and
  # must therefore touch only in-memory state.
  #
  # Hash#shift removes the oldest FIRST REGISTRATION, and Hash#[]= on an existing key does not
  # move it (verified fact 8), so an overwrite does not refresh a key's position. Oldest-first is
  # what CTX-13 explicitly permits; what it forbids is relying on any entry surviving, and no
  # caller of this map does.
  class BoundedMap
    # @param cap [Integer] the hard bound, a positive Integer
    def initialize(cap:)
      Model.required!("cap", cap)
      unless cap.is_a?(::Integer) && cap.positive?
        raise InvalidArgumentError, "cap must be a positive Integer"
      end

      @cap = cap
      @h = {} #: Hash[untyped, untyped]
      @mutex = ::Thread::Mutex.new
    end

    # Unconditional overwrite: install-or-replace. Never raises.
    #
    # @param key [Object] the slot
    # @param value [Object] its new occupant
    # @return [Object] `value`
    def set(key, value)
      @mutex.synchronize do
        @h[key] = value
        drain
      end
      value
    end

    # Reject-on-duplicate insert: install only if absent. Returns whether THIS call installed the
    # value; the caller decides what a false return means. Never raises -- the conflict is a
    # return value, not an exception, so ContextStore can raise its own error naming the key
    # AFTER this mutex is released (concurrency-and-async/f261a143).
    #
    # @param key [Object] the slot
    # @param value [Object] the occupant to install if the slot is empty
    # @return [Boolean] whether the value was installed
    def put(key, value)
      @mutex.synchronize do
        next false if @h.key?(key)

        @h[key] = value
        drain
        true
      end
    end

    # @param key [Object] the slot
    # @return [Object, nil] the occupant, or nil for an empty or evicted slot
    def [](key)
      @mutex.synchronize { @h[key] }
    end

    # Identity-conditional delete: removes the slot only when its current occupant is the object
    # handed in (`equal?`), never by value equality -- a structurally identical live sibling must
    # survive a stale context's close (CTX-9). Named for its mechanism, not for CTX-9: phase 6's
    # AUTH-19 counter store never calls it, and a general map should not carry a context-shaped
    # name. Absence is a no-op, not an error.
    #
    # @param key [Object] the slot
    # @param object [Object] the occupant that must be there for the slot to be cleared
    # @return [Boolean] whether the slot was cleared
    def delete_if_identical(key, object)
      @mutex.synchronize do
        next false unless @h.key?(key) && @h[key].equal?(object)

        @h.delete(key)
        true
      end
    end

    # @return [Integer] the number of live entries, at most the cap once inserts quiesce
    def size
      @mutex.synchronize { @h.size }
    end

    private

    # Called under the mutex, after a write. XCUT-14's loop; see the class comment for why it
    # runs at most once here.
    def drain
      @h.shift while @h.size > @cap
    end
  end
  private_constant :BoundedMap
end
