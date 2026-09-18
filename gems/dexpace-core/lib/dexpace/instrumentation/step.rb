# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "../pipeline/stages"
require_relative "../clock"
require_relative "../http/body/request_logging_body"
require_relative "../http/body/response_logging_body"
require_relative "keys"
require_relative "http_logging"
require_relative "logger"
require_relative "contain"
require_relative "emitter"
# Phase 4a's: NO_TRACER_FACTORY lives in no_tracer.rb and Bundle::NONE in bundle.rb.
require_relative "no_tracer"
require_relative "bundle"
# Phase 5c's: NO_METER lives in meter.rb, and Tracing.correlate in tracing.rb (R11).
require_relative "meter"
require_relative "tracing"

module Dexpace
  module Instrumentation
    # OBS-34, OBS-36, OBS-39 and OBS-20: the HTTP instrumentation step at Stages::LOGGING, the
    # object that ties the logging facade, 5c's tracing and metrics, and phase 3b's two logging
    # bodies to one exchange. Installed with `builder.append(step)` and no `stage:` argument,
    # because it declares #stage (4c); it drives the chain exactly once through Cursor#call and
    # never forks (4c: "a step that drives the chain exactly once drives it through #call").
    #
    # The body is one structural property, and OBS-34's independence clause is that property
    # seen from one side and OBS-20's asymmetry the same property seen from the other: the two
    # log emissions sit inside Instrumentation.contain under the level guard, and every tracer,
    # scope and meter call sits OUTSIDE both, in the `ensure`, unwrapped. So at level `none` no
    # log event is emitted while the span still starts and finishes and the counter and
    # histogram still record; and a sink that raises cannot fail the request while a tracer or
    # meter that raises WILL propagate and can (OBS-30's contract on the implementer). Neither
    # segment may make the other's rule uniform (boundary 3).
    #
    # The two slots are keywords defaulting to the constants the phase ships -- phase 4a's
    # NO_TRACER_FACTORY and phase 5c's NO_METER (P5-33) -- and the two instruments are created
    # once here, in .build, never per request (OBS-31). The reconciled precedence's three
    # clauses -- "the request context's bundle when it is not Bundle::NONE, else the step's
    # constructor keyword, else the constant" -- are honoured for the TRACER FACTORY since phase
    # 6a's Task 8 widened Cursor with #bundle: #open_span reads the cursor's bundle and takes its
    # tracer factory when the bundle is not Bundle::NONE, else this step's keyword (which is the
    # constant when nothing was passed), and Tracing.correlate is handed the same bundle, so a
    # populated one pushes its trace and span ids onto the diagnostic context (OBS-23). The
    # meter has no bundle source: CTX-14's bundle carries no meter and the two instruments are
    # created once at .build (OBS-31), so the meter's precedence is the keyword, then the
    # constant, and that is the whole of it. A call that seeds no bundle resolves exactly as
    # phase 5 did -- the keyword and Bundle::NONE, OBS-34's and XCUT-19(e)'s own default
    # configuration. The span is still named by the request's method token, which is also what
    # the tracer factory is asked for: the operation identifier is 4a's
    # RequestContext#operation_name and the cursor's bundle carries no name (P6-52).
    #
    # The level guard is read once at the top of #call and consulted at three sites -- the two
    # emissions and the body wrapping -- and a step that re-read it inside a helper would be one
    # refactor from a fourth site, and the fourth site is always the one that guards a span.
    class Step
      private_class_method :new

      # Builds a frozen step. The two instruments are manufactured here, once.
      #
      # @param logger [Logger] the facade every event goes through, whose redactor is also the
      #   policy that gates which header names are logged (P5-95: one policy per path)
      # @param level [HTTPLogging] the granularity; HTTPLogging::NONE emits no log event
      # @param tracer_factory [Object] a _TracerFactory; phase 4a's NO_TRACER_FACTORY by default
      # @param meter [Object] a _Meter; phase 5c's NO_METER by default
      # @param preview_bytes [Integer, nil] the body-preview cap the two logging bodies are built
      #   with; REQUIRED at HTTPLogging::BODY, and a positive Integer. No 8 KiB default lives
      #   here: OBS-36's "reference default 8 KiB" is a figure a caller resolves through
      #   `configuration.integer(Configuration::Keys::LOG_PREVIEW_BYTES, default: 8 * 1024)` and
      #   passes, because a silent default is a memory bound nobody chose (the plan's open
      #   question 5, P5-36's precedent)
      # @param clock [Object] a _Clock; the duration is measured with #monotonic and never #now
      #   (CFG-16)
      # @return [Step] frozen
      # @raise [Dexpace::InvalidArgumentError] for a level that is not an HTTPLogging, or for
      #   the body level without a positive preview_bytes
      def self.build(logger:, level:, tracer_factory: NO_TRACER_FACTORY, meter: NO_METER,
                     preview_bytes: nil, clock: Clock::SYSTEM)
        level!(level, preview_bytes)
        new(emitter: Emitter.new(logger: Model.required!("logger", logger), level: level),
            logger: logger, level: level, tracer_factory: tracer_factory,
            counter: meter.create_counter(Keys::INSTRUMENT_REQUEST_COUNT),
            histogram: meter.create_histogram(Keys::INSTRUMENT_REQUEST_DURATION),
            preview_bytes: preview_bytes, clock: clock,).freeze
      end

      # The level must be one of the three, and the body level needs its cap.
      def self.level!(level, preview_bytes)
        raise InvalidArgumentError, "level must be an HTTPLogging" unless level.is_a?(HTTPLogging)
        return unless level.at_least?(HTTPLogging::BODY)
        return if preview_bytes.is_a?(::Integer) && preview_bytes.positive?

        raise InvalidArgumentError, "preview_bytes is required"
      end
      private_class_method :level!

      def initialize(emitter:, logger:, level:, tracer_factory:, counter:, histogram:,
                     preview_bytes:, clock:)
        @emitter = emitter
        @logger = logger
        @level = level
        @tracer_factory = tracer_factory
        @counter = counter
        @histogram = histogram
        @preview_bytes = preview_bytes
        @clock = clock
      end

      # 4c's optional declaration, read once at install: this is a Stages::LOGGING pillar step.
      #
      # @return [Dexpace::Pipeline::Stage]
      def stage
        Pipeline::Stages::LOGGING
      end

      # Drives the chain once. Tracing is set up before the guarded region and torn down in its
      # `ensure`, unwrapped; the request event, the response event and the failure event run
      # inside Instrumentation.contain under the level guard; at the body level the outbound
      # body is wrapped in RequestLoggingBody and the inbound one in ResponseLoggingBody --
      # the only place in core that constructs either, which is what makes BODY-34's "engaged
      # only when body-level logging is enabled" structurally true.
      #
      # @param request [Dexpace::Request]
      # @param cursor [Dexpace::Pipeline::Cursor]
      # @return [Dexpace::Response] the response, its body wrapped at the body level
      def call(request, cursor)
        started = @clock.monotonic
        bundle = cursor.bundle
        span = open_span(request, bundle)
        scope = Tracing.correlate(span, bundle)
        begin
          request = prepare(request)
          response = cursor.call(request)
          response = wrap_response(response) if body?
          log_response(request, response, started)
          response
        rescue ::StandardError => error
          log_failure(request, error, started)
          raise
        ensure
          # OBS-20, OBS-30: not contained. A throwing scope, span or meter propagates.
          scope.close
          finish(span, started)
        end
      end

      private

      # 4a's #tracer, then 5c's #start_span, both named by the method token (see the class
      # comment). The factory is the cursor's bundle's when the call seeded one, else this
      # step's own: the reconciled precedence's first clause, live since phase 6a's Task 8.
      def open_span(request, bundle)
        name = request.method.to_s
        factory = bundle.equal?(Bundle::NONE) ? @tracer_factory : bundle.tracer_factory
        factory.tracer(name: name).start_span(name)
      end

      # 5c's #finish and the two instruments, unwrapped. `attributes:` is optional on both
      # instruments and none are passed: no OBS requirement fixes an attribute set for these
      # two, OBS-32's conventions are post-v1, and an inline Hash literal here would allocate
      # per request to carry a vocabulary nothing has chosen. The histogram takes milliseconds,
      # the same figure the log field carries.
      def finish(span, started)
        span.finish
        @counter.add(1)
        @histogram.record(elapsed_ms(started))
      end

      def elapsed_ms(started) = (@clock.monotonic - started) * 1000.0

      def logged? = @level.at_least?(HTTPLogging::HEADERS)
      def body? = @level.at_least?(HTTPLogging::BODY)

      # The request as the chain will see it -- its body wrapped at the body level -- and the
      # request event, contained.
      def prepare(request)
        request = wrap_request(request) if body?
        log_request(request)
        request
      end

      def log_request(request)
        return unless logged?

        Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) do
          @emitter.request(request)
        end
      end

      def log_response(request, response, started)
        return unless logged?

        Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) do
          @emitter.response(request, response, elapsed_ms(started))
        end
      end

      def log_failure(request, error, started)
        return unless logged?

        Instrumentation.contain(@logger, event: Events::INSTRUMENTATION_LOG) do
          @emitter.failure(request, error, elapsed_ms(started))
        end
      end

      # The body-logging caps' gate (OBS-36, BODY-34): phase 3b's wrappers, constructed only
      # here and only at the body level, with the cap this step was built with. 3b's over-cap
      # regime replays the captured prefix and continues from the live tail, so this class
      # writes no streaming code; it supplies the cap and the gate.
      def wrap_request(request)
        body = request.body
        cap = @preview_bytes
        return request if body.nil? || cap.nil?

        request.with(body: RequestLoggingBody.new(body, tap_limit: cap))
      end

      def wrap_response(response)
        body = response.body
        cap = @preview_bytes
        return response if body.nil? || cap.nil?

        response.with(body: ResponseLoggingBody.new(body, preview_bytes: cap))
      end
    end
  end
end
