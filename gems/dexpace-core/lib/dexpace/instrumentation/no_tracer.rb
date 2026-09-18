# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "no_span"

module Dexpace
  module Instrumentation
    # CTX-20's no-op tracer, the object behind NO_TRACER, returned by NO_TRACER_FACTORY#tracer,
    # with OBS-25's protocol as phase 5c gave it (the protocol phase 4a postponed): "a no-op
    # Tracer returning a shared no-op Span" is a reference-identity claim, and both methods hand
    # back the published NO_SPAN from arguments already on the stack, so the no-op path allocates
    # nothing (OBS-25; a four-keyword signature called with one positional argument measures at
    # the floor, verified fact 1). Every method works on a FROZEN receiver and none writes an
    # ivar. Named keywords, never a `**` splat (P5-42, Dexpace/NoKeywordSplat).
    #
    # The signatures are opentelemetry-api's Tracer#start_span and #in_span as a structural
    # subset (design §8.1, P4-8's argument): `with_parent:` and `kind:` are the gem's own
    # keywords; its `links:` and `start_timestamp:` are not mirrored, because nothing in this
    # SDK passes either and a locked keyword nothing passes is NFR-4 surface with no caller.
    #
    # The implementer contract, where a duck-typed SPI can bind it: OBS-29's "One tracer
    # instance corresponds 1:1 to a single logical operation lifecycle" binds a tracer that
    # accumulates per-operation STATE -- a recording tracer's factory returns a fresh instance
    # per operation -- and does not bind this stateless one, which NO_TRACER_FACTORY returns
    # shared on every call as OBS-25 requires; the two MUSTs are consistent only so read (P5-43).
    # Every method is safe to invoke concurrently and never raises (OBS-30).
    class NoTracer
      # rubocop:disable Lint/UnusedMethodArgument -- the arguments are the documented protocol
      # and are ignored by construction; OBS-25 requires the shared singleton back regardless.

      # OBS-25: the shared no-op span, whatever it is asked to start.
      #
      # @param name [String] the span name
      # @param attributes [Hash{String => Object}, nil] initial attributes, frozen by the caller
      # @param kind [Symbol, nil] the span kind (:client for an outbound request)
      # @param with_parent [Object, nil] an explicit parent context, else the current span
      # @return [Object] NO_SPAN, always
      def start_span(name, attributes: nil, kind: nil, with_parent: nil)
        NO_SPAN
      end

      # OBS-25: yields the shared no-op span and returns the block's value; without a block,
      # the span itself. A raise inside the block is the caller's (OBS-30: nothing rescues).
      #
      # @param name [String] the span name
      # @param attributes [Hash{String => Object}, nil] initial attributes, frozen by the caller
      # @param kind [Symbol, nil] the span kind
      # @yieldparam span [Object] NO_SPAN
      # @return [Object] the block's value, or NO_SPAN without a block
      def in_span(name, attributes: nil, kind: nil)
        return NO_SPAN unless block_given?

        yield NO_SPAN
      end
      # rubocop:enable Lint/UnusedMethodArgument
    end
    private_constant :NoTracer

    # The one shared, frozen no-op tracer. Public rather than private for the same reason
    # NO_SPAN is: OBS-25's allocation clause is asserted as
    # `assert_same Dexpace::Instrumentation::NO_TRACER, factory.tracer`, a qualified reference.
    NO_TRACER = NoTracer.new.freeze

    # CTX-20's no-op tracer factory, the class behind NO_TRACER_FACTORY. Not empty: CTX-20's
    # embedded MUST ("Its factory method MUST be safe to invoke concurrently from multiple
    # threads") forbids that -- a factory with no factory method cannot satisfy a MUST about that
    # method. It holds no state, so the concurrency safety is structural.
    #
    # #tracer's name and its parameter list mirror opentelemetry-api's own
    # OpenTelemetry::Trace::TracerProvider#tracer (opentelemetry-api 1.11.0,
    # lib/opentelemetry/trace/tracer_provider.rb, fetched from rubygems.org and read 2026-09-08
    # by the plan and again 2026-09-16 at implementation) rather than this repository's own
    # keywords-everywhere rule (api-design/1d9e6e0b), because being call-compatible with a
    # foreign TracerProvider is this method's entire purpose (P4-8): an application already
    # running OpenTelemetry must be able to pass OpenTelemetry.tracer_provider straight into
    # Bundle.build(tracer_factory:). The gem keeps the two legacy positional parameters for
    # callers written against its older two-argument form while the keyword arguments take
    # precedence on the same slot; all five are ignored here. Named parameters, never a `**`
    # splat: Dexpace/NoKeywordSplat, because a splat allocates a Hash per call and OBS-25's no-op
    # path may allocate nothing.
    class NoTracerFactory
      # The one method CTX-20 forces into existence. Every argument is part of the mirrored
      # signature and deliberately unused; see the class comment and P4-8.
      #
      # @param deprecated_name [String, nil] the gem's legacy positional instrumentation name
      # @param deprecated_version [String, nil] the gem's legacy positional version
      # @param name [String, nil] the instrumentation-library name
      # @param version [String, nil] the instrumentation-library version
      # @param attributes [Hash, nil] instrumentation-scope attributes
      # @return [Object] NO_TRACER, always, so selecting the no-op path allocates nothing
      # rubocop:disable-next Lint/UnusedMethodArgument
      def tracer(deprecated_name = nil, deprecated_version = nil, name: nil, version: nil,
                 attributes: nil)
        NO_TRACER
      end
    end
    private_constant :NoTracerFactory

    # The one shared, frozen no-op tracer factory (CTX-14's "a per-operation tracer factory",
    # CTX-15, CTX-20). Its #tracer returns NO_TRACER from every thread, which is OBS-25's
    # allocation clause and CTX-20's thread-safety clause in one assertion.
    NO_TRACER_FACTORY = NoTracerFactory.new.freeze
  end
end
