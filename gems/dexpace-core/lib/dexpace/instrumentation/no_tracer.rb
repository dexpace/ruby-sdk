# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Instrumentation
    # CTX-20's no-op tracer, the object behind NO_TRACER, returned by NO_TRACER_FACTORY#tracer.
    # Responds to nothing beyond Object's own surface for the reason NoSpan does: the tracer
    # protocol is OBS-21..OBS-25, phase 5c's, and it lands as methods on this private class.
    class NoTracer; end # rubocop:disable Lint/EmptyClass -- postponed protocol: phase 5c adds it.
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
