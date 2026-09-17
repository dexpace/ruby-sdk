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

    # OBS-1 and OBS-3 through OBS-9, OBS-39 and OBS-40: the structured log event -- a mutable
    # accumulator of fields, one categorisation tag and one cause, with a single terminal
    # #emit. Obtained only from Logger#event, which decides enabled or disabled ONCE and hands
    # back either a live instance or the shared, frozen Event::INERT (OBS-1). A plain class and
    # not a Data (P5-21): OBS-8 says accumulation "is not required to be thread-safe
    # (single-thread build)", which describes a mutable object, and a frozen value cannot
    # accumulate. `new` is private; Logger reaches it the way the pipeline driver reaches
    # Cursor's.
    #
    # Redaction runs on the way INTO #field and never at the sink (design §8.1, boundary 5), and
    # the mechanism is a reserved-key table keyed by the field NAME: `url.full` goes through
    # Redactor#url, and a key under either header prefix goes through OBS-18's name gate and
    # then, for an allow-listed name, Redactor#header_value -- whoever the caller is. That is
    # what makes OBS-39's "the logged url.full MUST always be the redacted URL" and OBS-18's "MUST
    # NOT have its value logged" structural rather than defended (P5-102), and it is why no sink
    # and no caller can bypass either: the header prefixes are reserved names, so a credential
    # header written straight into #field is marked or dropped exactly as the step's are.
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
        header = header_of(name)
        if header.nil?
          @fields[name] = name == Keys::URL_FULL ? @redactor.url(value) : value
        else
          header_field(name, header, value)
        end
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
      # this event's fields, later winning -- into one Hash, so a key appears at most once;
      # writes the tag over any `event` key the three sources supplied (OBS-4, with OBS-40's
      # once-per-logger diagnostic when the colliding key was a per-event field, and silence when
      # it came from the ambient context); attaches the cause; renders every value totally
      # (OBS-6, OBS-7); and hands the record to the sink through the block form of the severity's
      # method, so a sink whose own level moved after creation still renders nothing.
      #
      # @return [nil]
      def emit
        return nil unless claim_emit!

        record = Diagnostics.folded(@diagnostic_keys)
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

      # The reserved-key table's header half (design §8.1): the header name behind a key under
      # either prefix, or nil for any other key. The field's NAME decides, never the call site.
      def header_of(name)
        if name.start_with?(Keys::HTTP_REQUEST_HEADER_PREFIX)
          name.delete_prefix(Keys::HTTP_REQUEST_HEADER_PREFIX)
        elsif name.start_with?(Keys::HTTP_RESPONSE_HEADER_PREFIX)
          name.delete_prefix(Keys::HTTP_RESPONSE_HEADER_PREFIX)
        end
      end

      # OBS-18 first, by name: a header outside the allow-list is stored as the marker or, in
      # the policy's omit mode, not stored -- the boolean's two modes at the one place every
      # header field passes through, so a caller and the step get the same answer (P5-102). An
      # allow-listed header's value then takes OBS-16's and OBS-17's route through the value
      # redactor, except a nil, which is OBS-3's literal null and not the redactor's --
      # `nil.equal?(value)` and not `value.nil?`, because a BasicObject answers no #nil? and
      # OBS-6 renders it anyway.
      def header_field(name, header, value)
        if @redactor.header_name?(header)
          @fields[name] = nil.equal?(value) ? nil : @redactor.header_value(header, value)
        elsif !@redactor.policy.omit_disallowed_headers
          @fields[name] = Redactor::REDACTED_HEADER
        end
      end
    end
  end
end
