# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # OBS-10 and OBS-24: the diagnostic-context carrier's three functions -- the whole-map
    # snapshot, the cross-thread bridge that installs and restores it, and the fold that puts
    # the context's keys on a log event -- and the two key names OBS-23 pushes and OBS-10 folds
    # by default. Phase 5c shipped the three constants early because Tracing.correlate and
    # Scope#close read the two keys (P5-71); phase 5b extended this file with the functions. It
    # requires nothing, deliberately: 5c's independence subprocess loads it by name and must not
    # acquire the logging half behind Tracing (R11).
    #
    # The carrier is `Fiber[]` and never `Thread.current[]` or Dexpace::ContextStore (boundary
    # 14): a value set before a child fiber, a new Thread or an Enumerator's fiber is created is
    # visible inside each, and `Thread.current[]`, despite its name, is fiber-local and visible
    # in none of them. Every write is per key through `Fiber[]=`, which warns nowhere; the
    # whole-map `Fiber#storage=` warns on every call at the default level on every supported
    # Ruby, against a gate set that fails the build on a warning, and is never called in lib/
    # (P5-23). The one thing that costs is the floor: `Fiber[:k] = nil` deletes the key on Ruby
    # 3.3 and later and leaves it present with a nil value on 3.2, whose Fiber API offers no
    # other removal -- so on 3.2 a restore returns a key the snapshot introduced to
    # present-and-nil rather than absent, which `Fiber[]` reads identically and the fold skips
    # identically (P5-72, applied to OBS-24; the checklist's floor decision).
    #
    # Symbols, not frozen Strings: Fiber.current.storage -- OBS-10's unfiltered reader -- hands
    # every key back as a Symbol, Fiber#storage= refuses a String key with TypeError on every
    # supported Ruby, and on the 3.2 and 3.3 rows Fiber[]= and Fiber[] refuse one too (measured
    # 2026-09-17; the interning the corpus records arrives at 3.4). A Symbol is the one spelling
    # every carrier API accepts on every row, and Symbol#name is the fold's allocation-free
    # bridge to OBS-39's String field key (5b's R11, 5c's verified fact 3, P5-24).
    module Diagnostics
      # OBS-23's first key, "trace.id", as the carrier spells it.
      TRACE_ID = :"trace.id"

      # OBS-23's second key, "span.id", as the carrier spells it.
      SPAN_ID = :"span.id"

      # OBS-10's default allow-list: "exactly {trace.id, span.id}", in that order.
      DEFAULT_KEYS = [TRACE_ID, SPAN_ID].freeze

      # P5-39: fiber-storage keys under this prefix are core's own slots and are never folded,
      # in either mode. 5c's private :"dexpace.current_span" holds a live Span; it is a carrier
      # for the tracing half, not a diagnostic-context key, and OBS-10's unfiltered mode would
      # otherwise put that object through OBS-6's rendering on every event. Public, because an
      # application that puts its own key under "dexpace." has to be able to read why it never
      # appears. No key this module declares starts with it.
      RESERVED_PREFIX = "dexpace."

      # OBS-24's "immutable snapshot": the current fiber's diagnostic context as a frozen Hash
      # of its present keys. One read and one freeze -- `Fiber.current.storage` already returns
      # a fresh, unfrozen copy on every call (verified fact 2), so there is nothing to duplicate
      # -- normalised from the `nil` an opted-out fiber reads on 3.3+ and the `{}` the 3.2 floor
      # reads instead. A nil-valued key is not a diagnostic-context value (OBS-10 skips it) and
      # is dropped here, so a snapshot has one shape on every row: on 3.2 the storage carries a
      # nil for every key ever set and cleared, and on 3.3+ only the warned whole-map setter can
      # produce one. Frozen is what is claimed; Ractor-shareable is not (P5-22): the values are
      # the host's, and `Ractor.make_shareable` on an unshareable value would raise from a
      # logging path, which XCUT-20 forbids.
      #
      # @return [Hash{Symbol => Object}] frozen, the present keys and their values
      def self.capture
        storage = current_storage
        storage.compact!
        storage.freeze
      end

      # OBS-24's bridge: installs `snapshot` on the current fiber for the block, then restores
      # the prior context -- "including on exception", through the `ensure` -- per key over the
      # union of the prior and the snapshot key sets, through `Fiber[]=` alone (P5-23). On Ruby
      # 3.3 and later the restore is exact: an overwritten key gets its prior value back and an
      # introduced key is removed. On the 3.2 floor an introduced key stays present with a nil
      # value (P5-72), which every reader of the diagnostic context -- `Fiber[]`, and the fold's
      # null-skip -- reads as absent. The one prior context no row restores exactly is one holding
      # a literal nil, which only `Fiber#storage=` can build; it comes back as absent on 3.3+ and
      # unchanged on 3.2. Mutations inside the block affect only the calling fiber: a child
      # thread or fiber inherits a copy-on-write view (verified fact 2).
      #
      # The snapshot is anything answering #each (pairs) and #keys, so a frozen Hash from
      # .capture, a merged one, or a caller's own object all serve.
      #
      # @param snapshot [Hash{Symbol => Object}, #each, #keys] the captured context to install
      # @yield with the snapshot installed
      # @return [Object] the block's value
      def self.with(snapshot)
        prior = current_storage
        begin
          snapshot.each { |key, value| ::Fiber[key] = value }
          yield
        ensure
          restore(prior, snapshot)
        end
      end

      # The current fiber's storage as a Symbol-keyed Hash: `{}` where an opted-out fiber reads
      # nil (3.3+) or `{}` (the 3.2 floor). rbs types the keys as `interned`; the carrier hands
      # back Symbols (verified), hence the untyped read.
      def self.current_storage
        storage = ::Fiber.current.storage #: untyped
        storage = {} if storage.nil? #: Hash[Symbol, untyped]
        storage
      end
      private_class_method :current_storage

      # The per-key union restore (P5-23), one assignment per key with no branch on presence.
      def self.restore(prior, snapshot)
        (prior.keys | snapshot.keys).each { |key| ::Fiber[key] = prior[key] }
      end
      private_class_method :restore

      # OBS-10's fold: the diagnostic-context keys an event carries, keyed by OBS-39's String
      # spelling, with every nil-valued key skipped. Two modes and two readers. With an
      # allow-list, each listed key is read through `Fiber[]`, where a nil-valued key and an
      # absent one are indistinguishable. With `nil` -- the opt-in unfiltered mode, "fold every
      # present diagnostic-context key" -- the whole map is read through `Fiber.current.storage`,
      # the one reader that can answer it, and there a nil-valued key is present and skipped
      # (R12: this is where the null clause is live), as is every key under RESERVED_PREFIX
      # (P5-39). The key bridge is `Symbol#name`, the same frozen String on every call, never
      # `#to_s`, which allocates one String per key per event on the path OBS-1 protects.
      #
      # @param allow_list [Array<Symbol>, nil] the keys to fold, or nil for every present key
      # @return [Hash{String => Object}] a fresh, unfrozen Hash the event merges into
      def self.folded(allow_list)
        allow_list.nil? ? fold_every_present_key : fold_listed_keys(allow_list)
      end

      # The unfiltered mode, over the whole map: nil values and reserved slots skipped.
      def self.fold_every_present_key
        folded = {} #: Hash[String, untyped]
        current_storage.each do |key, value|
          next if value.nil?

          name = key.name
          folded[name] = value unless name.start_with?(RESERVED_PREFIX)
        end
        folded
      end
      private_class_method :fold_every_present_key

      # The allow-listed mode, per key through `Fiber[]`: nil values skipped.
      def self.fold_listed_keys(allow_list)
        folded = {} #: Hash[String, untyped]
        allow_list.each do |key|
          value = ::Fiber[key]
          folded[key.name] = value unless value.nil?
        end
        folded
      end
      private_class_method :fold_listed_keys
    end
  end
end
