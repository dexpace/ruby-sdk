# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "severity"
require_relative "keys"
require_relative "render"
require_relative "diagnostics"
require_relative "redactor"

module Dexpace
  module Instrumentation
    # The once-per-logger latch behind OBS-40's collision diagnostic: claimed exactly once,
    # under the logger's mutex, by whichever event first sees a per-event `event` field collide
    # with a tag. Held by the Logger and shared by every event it creates. A private_constant of
    # the namespace, reachable by its bare name from Logger and Event alike; it is the mechanism
    # and not a service.
    class CollisionLatch
      def initialize(mutex)
        @mutex = mutex
        @claimed = false
      end

      # True for the first caller and false for every later one.
      #
      # @return [Boolean]
      def claim
        @mutex.synchronize do
          if @claimed
            false
          else
            @claimed = true
          end
        end
      end
    end
    private_constant :CollisionLatch

    # The reserved-key table (design §8.1): the redaction a field NAME selects, whoever supplied
    # the value. `url.full` goes through Redactor#url; a key under either header prefix goes
    # through OBS-18's name gate and then, for an allow-listed name, Redactor#header_value; every
    # other key is identity. One table, applied to all three of OBS-5's sources -- a per-event
    # field at Event#field, the logger's global context once at Logger.build, and the folded
    # diagnostic context at Event#emit (P5-104) -- because OBS-39's "the logged url.full MUST
    # always be the redacted URL" and OBS-18's "MUST NOT have its value logged" are stated on
    # the emitted record and not on one entry point: a reserved key put in the context or in the
    # diagnostic context reached the sink raw before review round 1 (R1-2). A private_constant of
    # the namespace, reachable by its bare name from Logger and Event alike.
    module ReservedKeys
      # The answer for a header OBS-18's omit mode drops: distinguishable from every value a
      # caller could pass, nil included, by identity.
      OMIT = ::Object.new.freeze

      # The value `name` is stored with, or OMIT.
      #
      # @param redactor [Redactor] the path's one policy (P5-95)
      # @param name [String] the field key
      # @param value [Object] the value as supplied
      # @return [Object]
      def self.value(redactor, name, value)
        header = header_of(name)
        if header.nil?
          name == Keys::URL_FULL ? redactor.url(value) : value
        elsif redactor.header_name?(header)
          header_value(redactor, header, value)
        elsif redactor.policy.omit_disallowed_headers
          OMIT
        else
          Redactor::REDACTED_HEADER
        end
      end

      # An allow-listed header's logged value. A multi-valued header -- an Array, which is what
      # the Emitter hands over for every header, and what a caller writing one by hand may pass
      # -- goes through the redactor ONE VALUE AT A TIME and is joined with ", ", the wire's own
      # combination rule, only afterwards (P5-108): joined first, a second `Location`'s userinfo
      # sat behind the first value's path, where the URL-value redactor -- which reads one URL
      # -- never reached it, and OBS-17's "redacted through the URL-value redactor" is stated
      # per value (review round 2's R2-2). nil is OBS-3's literal null and not the redactor's
      # "". A `case`, because `when` sends `===` to the pattern and nothing to the value: a
      # BasicObject answers no `#is_a?` and no `#nil?`, and OBS-6 renders it anyway.
      #
      # @param redactor [Redactor]
      # @param header [String] the header name behind the key
      # @param value [Object] one value, an Array of them, or nil
      # @return [Object]
      def self.header_value(redactor, header, value)
        case value
        when ::Array then value.map { |each| redactor.header_value(header, each) }.join(", ")
        when nil then nil
        else redactor.header_value(header, value)
        end
      end

      # Applies the table to every reserved key of `hash` in place, leaving every other key
      # untouched, and answers the hash. Runs on the enabled path only, where an Array of the
      # keys is an allocation OBS-1 does not constrain.
      #
      # @param redactor [Redactor]
      # @param hash [Hash{String => Object}] String-keyed, mutable
      # @return [Hash{String => Object}] the same hash
      def self.scrub!(redactor, hash)
        hash.keys.each do |name|
          next unless reserved?(name)

          stored = value(redactor, name, hash[name])
          stored.equal?(OMIT) ? hash.delete(name) : hash[name] = stored
        end
        hash
      end

      # Whether the table has an entry for `name`.
      #
      # @param name [String]
      # @return [Boolean]
      def self.reserved?(name)
        name == Keys::URL_FULL || !header_of(name).nil?
      end

      # The header name behind a key under either prefix, or nil for any other key.
      #
      # @param name [String]
      # @return [String, nil]
      def self.header_of(name)
        if name.start_with?(Keys::HTTP_REQUEST_HEADER_PREFIX)
          name.delete_prefix(Keys::HTTP_REQUEST_HEADER_PREFIX)
        elsif name.start_with?(Keys::HTTP_RESPONSE_HEADER_PREFIX)
          name.delete_prefix(Keys::HTTP_RESPONSE_HEADER_PREFIX)
        end
      end
    end
    private_constant :ReservedKeys

    # OBS-1 and OBS-3 through OBS-9, OBS-39 and OBS-40: the structured log event -- a mutable
    # accumulator of fields, one categorisation tag and one cause, with a single terminal
    # #emit. Obtained only from Logger#event, which decides enabled or disabled ONCE and hands
    # back either a live instance or the shared, frozen Event::INERT (OBS-1). A plain class and
    # not a Data (P5-21): OBS-8 says accumulation "is not required to be thread-safe
    # (single-thread build)", which describes a mutable object, and a frozen value cannot
    # accumulate. `new` is private; Logger reaches it the way the pipeline driver reaches
    # Cursor's.
    #
    # Redaction runs on the way INTO the record and never at the sink (design §8.1, boundary 5),
    # and the mechanism is ReservedKeys, a table keyed by the field NAME: `url.full` goes through
    # Redactor#url, and a key under either header prefix goes through OBS-18's name gate and
    # then, for an allow-listed name, Redactor#header_value -- whoever the caller is and
    # whichever of OBS-5's three sources supplied it. A per-event field meets the table at
    # #field, the logger's global context met it once at Logger.build, and the folded diagnostic
    # context meets it at #emit (P5-102, P5-104). That is what makes OBS-39's "the logged url.full
    # MUST always be the redacted URL" and OBS-18's "MUST NOT have its value logged" structural
    # rather than defended, and it is why no sink and no caller can bypass either: the header
    # prefixes are reserved names, so a credential header written straight into #field, put in
    # the context or set in `Fiber[]` is marked or dropped exactly as the step's are.
    #
    # #emit is at most once (OBS-8): a flag flipped under the logger's Thread::Mutex, with the
    # mutex RELEASED before the sink is called. Not prudence -- Thread::Mutex is per-fiber-owned
    # and non-reentrant, so a sink whose #debug block yielded to another fiber of the same
    # thread would deadlock inside the lock (verified fact 12). Not a bare flag either: a lone
    # boolean flip is atomic on CRuby and not on JRuby or TruffleRuby, and §1 fixes safe
    # publication as the port's rule.
    class Event
      private_class_method :new

      # OBS-1's disabled path (P5-20): every builder method returns self, #emit returns nil, no
      # instance variable is ever written, so the one frozen instance is safe from any thread and
      # its chain allocates nothing (R8). A subclass, so `is_a?(Event)` stays true and
      # Logger#event's return type stays one class; built with .allocate because the initializer
      # takes collaborators an inert event has no use for.
      class Inert < Event
        # Discards the field.
        #
        # @return [self]
        def field(_key, _value)
          self
        end

        # Discards the tag.
        #
        # @return [self]
        def event(_name)
          self
        end

        # Discards the cause.
        #
        # @return [self]
        def cause(_error)
          self
        end

        # Emits nothing.
        #
        # @return [nil]
        def emit
          nil
        end
      end
      private_constant :Inert

      # OBS-1's shared inert event, the object Logger#event returns for a disabled severity.
      # Public, because OBS-1's conformance clause asserts "reference-identical across calls" by
      # a qualified constant from another gem (R8), and a private_constant is unreachable that
      # way.
      INERT = Inert.allocate.freeze

      # OBS-40's message, a String at the sink's debug level.
      COLLISION_MESSAGE = "dexpace: a per-event field named 'event' collided with the event " \
                          "tag and was dropped; the tag wins (OBS-40)"
      private_constant :COLLISION_MESSAGE

      def initialize(severity:, sink:, redactor:, context:, diagnostic_keys:, mutex:, latch:)
        @severity = severity
        @sink = sink
        @redactor = redactor
        @context = context
        @diagnostic_keys = diagnostic_keys
        @mutex = mutex
        @latch = latch
        @fields = {} #: Hash[String, untyped]
        @tag = nil
        @cause = nil
        @emitted = false
      end

      # Adds one field, redacting on the way in when the key is reserved (OBS-11..OBS-18,
      # OBS-39). The key must be a non-empty String or Symbol (OBS-3, through Model.required! so
      # the message is SEAM-29's one form); a later #field with the same key replaces the
      # earlier. A nil value is kept and renders as the literal "null" at #emit (OBS-3) -- it is
      # not routed through the header redactor, whose contract would turn it into "". A key
      # under either header prefix whose header name is not allow-listed stores the fixed
      # REDACTED marker or, when the policy says omit, nothing at all (OBS-18, P5-102).
      #
      # @param key [String, Symbol] the field name; a Symbol is taken by its name
      # @param value [Object] anything; rendered totally at #emit (OBS-6)
      # @return [self]
      # @raise [Dexpace::InvalidArgumentError] for a nil, empty or non-name key
      def field(key, value)
        name = field_name!(key)
        stored = ReservedKeys.value(@redactor, name, value)
        @fields[name] = stored unless stored.equal?(ReservedKeys::OMIT)
        self
      end

      # OBS-4: sets the categorisation tag emitted under the reserved `event` key, exactly once.
      # A nil or empty name CLEARS the tag rather than emitting `event=`.
      #
      # @param name [String, Symbol, nil] the tag, or nothing
      # @return [self]
      def event(name)
        @tag = name.nil? || name.to_s.empty? ? nil : Model.frozen_string(name.to_s)
        self
      end

      # OBS-39's "the throwable cause attached": rendered as `SimpleClassName: message` under
      # Keys::CAUSE at #emit. nil clears it.
      #
      # @param error [Exception, nil]
      # @return [self]
      def cause(error)
        @cause = error
        self
      end

      # The terminal emit, at most once (OBS-8), from any thread. Merges the three sources in
      # OBS-5's precedence -- folded diagnostic context, then the logger's global context, then
      # this event's fields, later winning -- into one Hash, so a key appears at most once, the
      # fold's reserved keys redacted through the same table the other two sources already met
      # (P5-104); writes the tag over any `event` key the three sources supplied (OBS-4, with
      # OBS-40's once-per-logger diagnostic when the colliding key was a per-event field, and
      # silence when it came from the ambient context); attaches the cause; renders every value
      # totally (OBS-6, OBS-7); and hands the record to the sink through the block form of the
      # severity's method, so a sink whose own level moved after creation still renders nothing.
      #
      # @return [nil]
      def emit
        return nil unless claim_emit!

        record = ReservedKeys.scrub!(@redactor, Diagnostics.folded(@diagnostic_keys))
        record.merge!(@context)
        record.merge!(@fields)
        apply_tag!(record)
        record[Keys::CAUSE] = @cause unless nil.equal?(@cause)
        record.transform_values! { |value| Render.render(value) }
        @sink.public_send(@severity.sink_method) { record }
        nil
      end

      private

      # OBS-8's guard: the flag flips under the mutex and the mutex is released before anything
      # else happens. True for exactly one caller per event.
      def claim_emit!
        @mutex.synchronize do
          if @emitted
            false
          else
            @emitted = true
          end
        end
      end

      # OBS-4 and OBS-40. When a tag is set it wins over every `event` key the sources supplied;
      # only a PER-EVENT field is worth warning about, because the caller wrote it, and the
      # warning costs nothing unless the sink's verbose level is on and the latch is unclaimed.
      def apply_tag!(record)
        tag = @tag
        return if tag.nil?

        record[Keys::EVENT] = tag
        return unless @fields.key?(Keys::EVENT) && @sink.debug? && @latch.claim

        @sink.debug { COLLISION_MESSAGE }
      end

      # OBS-3: nil, a non-name and an empty name all take one route, Model.required!, so the
      # message is SEAM-29's one form.
      def field_name!(key)
        name =
          case key
          when ::Symbol then key.name
          when ::String then Model.frozen_string(key)
          end
        Model.required!("field key", name.nil? || name.empty? ? nil : name)
      end
    end
  end
end
