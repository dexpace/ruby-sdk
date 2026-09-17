# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "severity"
require_relative "null_sink"
require_relative "diagnostics"
require_relative "redactor"
require_relative "event"

module Dexpace
  module Instrumentation
    # OBS-1, OBS-2, OBS-9, OBS-10 and OBS-40: the facade every log event is obtained from. A
    # plain class (P5-21) holding a sink, a frozen global context, a redactor, the diagnostic
    # allow-list, one Thread::Mutex and OBS-40's once-per-logger latch; frozen after
    # construction, so every Logger -- Logger::NULL included -- is safe to share from any thread.
    #
    # It keeps design §8.1's name, `Logger`, and that name shadows the stdlib `Logger` for a bare
    # reference written INSIDE `module Dexpace; module Instrumentation` (P5-38) -- and only
    # there: from anywhere else inside `module Dexpace` a bare `Logger` still resolves to Ruby's,
    # because this constant is Dexpace::Instrumentation::Logger and not Dexpace::Logger, so the
    # shadow sits outside the shape Dexpace/QualifiedCoreConstant expresses. Core never loads the
    # stdlib one (boundary 1), so inside this namespace the bare name can mean nothing else;
    # every reference from outside it is written `Instrumentation::Logger`.
    class Logger
      private_class_method :new

      # The eight methods the sink duck type comprises (design §8.1's structural subset of the
      # stdlib Logger surface): the four severity writes and their four predicates.
      SINK_METHODS = %i[debug info warn error debug? info? warn? error?].freeze
      private_constant :SINK_METHODS

      # The installed sink, so a caller composing a second logger over it can read it.
      #
      # @return [Object] the _Sink
      attr_reader :sink

      # OBS-9's global context: the frozen String-keyed Hash attached to every event this logger
      # emits, the same object every time -- referenced, never copied per event, which is why it
      # is frozen at construction rather than hoped immutable.
      #
      # @return [Hash{String => Object}] frozen
      attr_reader :context

      # The redactor every event this logger creates redacts through, and the ONE redaction
      # policy of a logging path (P5-95): the instrumentation step takes no redactor of its own,
      # and every header field -- the step's and a caller's alike -- is gated by name and
      # redacted by value through this one at Event#field (P5-102), so the names a step logs and
      # the values its events redact cannot come from two policies. Public so the path's policy
      # is observable and a later phase can derive one with RedactionPolicy#with.
      #
      # @return [Redactor]
      attr_reader :redactor

      # Builds a frozen logger.
      #
      # @param sink [Object] anything answering the _Sink duck type; NULL_SINK when omitted
      # @param context [Hash] OBS-9's global key/value context; keys are taken by their String
      #   form and the whole is deep-frozen once here
      # @param redactor [Redactor] the redaction applied on the way into every Event#field
      # @param diagnostic_keys [Array<Symbol>, nil] OBS-10's allow-list; nil is a MODE, the
      #   opt-in unfiltered fold of every present diagnostic-context key, and not "use the
      #   default" -- which is the one place api-design/6ea28c9c's "never nil for absent" is
      #   overruled by requirement
      # @return [Logger]
      # @raise [Dexpace::InvalidArgumentError] for a sink missing one of the eight methods, a
      #   context that is not a Hash, or a key list that is not a list of names
      def self.build(sink: NULL_SINK, context: {}, redactor: Redactor::DEFAULT,
                     diagnostic_keys: Diagnostics::DEFAULT_KEYS)
        mutex = ::Thread::Mutex.new
        new(sink: sink!(sink), context: context!(context),
            redactor: Model.required!("redactor", redactor),
            diagnostic_keys: diagnostic_keys!(diagnostic_keys), mutex: mutex,
            latch: CollisionLatch.new(mutex),).freeze
      end

      def initialize(sink:, context:, redactor:, diagnostic_keys:, mutex:, latch:)
        @sink = sink
        @context = context
        @redactor = redactor
        @diagnostic_keys = diagnostic_keys
        @mutex = mutex
        @latch = latch
      end

      # OBS-1: the enabled decision, made ONCE, here -- the sink's predicate for the severity --
      # and a live Event or the shared Event::INERT accordingly. The inert path allocates
      # nothing; the live one allocates the event and its field Hash, which OBS-1 does not ask
      # to be free.
      #
      # @param severity [Severity, Symbol] a Severity, or its name
      # @return [Event] a live event, or Event::INERT
      def event(severity)
        resolved = resolve(severity)
        return Event::INERT unless @sink.public_send(resolved.sink_predicate)

        Event.send(:new, severity: resolved, sink: @sink, redactor: @redactor,
                         context: @context, diagnostic_keys: @diagnostic_keys, mutex: @mutex,
                         latch: @latch,)
      end

      # Whether the sink has the severity's level on: the one query the step and a caller share,
      # and OBS-40's verbose gate.
      #
      # @param severity [Severity, Symbol] a Severity, or its name
      # @return [Boolean]
      def enabled?(severity)
        @sink.public_send(resolve(severity).sink_predicate) ? true : false
      end

      # Fails fast on a sink missing any of the eight methods, naming the first one missing.
      def self.sink!(sink)
        missing = SINK_METHODS.find { |name| !sink.respond_to?(name) }
        return sink if missing.nil?

        raise InvalidArgumentError,
              "sink must respond to #{SINK_METHODS.map { |name| "##{name}" }.join(", ")}; " \
              "#{sink.class} lacks ##{missing}"
      end
      private_class_method :sink!

      # A String-keyed copy, deep-frozen once (Model.own), so OBS-9's "referenced, not
      # deep-copied per event" is safe and "effectively immutable" is enforced.
      def self.context!(context)
        unless context.is_a?(::Hash)
          raise InvalidArgumentError, "context must be a Hash, got #{context.class}"
        end

        Model.own(context.to_h { |key, value| [key.to_s, value] })
      end
      private_class_method :context!

      # nil stays nil (the unfiltered mode); a list becomes a frozen Array of Symbols, because a
      # String key raises TypeError at `Fiber[]` on the 3.2 and 3.3 rows.
      def self.diagnostic_keys!(keys)
        return nil if keys.nil?
        unless keys.respond_to?(:map) && !keys.is_a?(::String)
          raise InvalidArgumentError,
                "diagnostic_keys must be nil or a list of names, got #{keys.class}"
        end

        keys.map do |key|
          unless key.is_a?(::Symbol) || key.is_a?(::String)
            raise InvalidArgumentError, "diagnostic_keys holds #{key.inspect}, which is not a name"
          end

          key.to_sym
        end.freeze
      end
      private_class_method :diagnostic_keys!

      # A frozen logger over NULL_SINK: the value a component with no logger installed holds, so
      # no caller ever branches on a nil logger (P5-17, Bundle::NONE's decision). Every #event on
      # it is Event::INERT. Assigned after the three validators exist: the class body runs top to
      # bottom and .build calls them.
      NULL = build

      private

      def resolve(severity)
        severity.is_a?(Severity) ? severity : Severity.of(severity)
      end
    end
  end
end
