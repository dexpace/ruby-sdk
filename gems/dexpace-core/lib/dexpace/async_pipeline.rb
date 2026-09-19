# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "closeable"
require_relative "http/request_options"
require_relative "cancellation"
require_relative "instrumentation/bundle"
require_relative "async/future"
require_relative "pipeline"
require_relative "pipeline/cursor"
require_relative "pipeline/async_driver"
require_relative "pipeline/builder"
require_relative "pipeline/entry"
require_relative "pipeline/stages"
require_relative "instrumentation/async_step"
require_relative "instrumentation/http_logging"
require_relative "instrumentation/logger"
require_relative "resilience/async_retry_step"
require_relative "resilience/retry_settings"
require_relative "error/invalid_argument_error"

module Dexpace
  # The asynchronous stage-based execution pipeline (design §5.3; PIPE-28, P4-36): the same
  # sixteen stages, the same builder, the same cursor, over an async transport, returning a
  # Dexpace::Async::Future per send.
  #
  # It has no Stages of its own, no Builder of its own and no Cursor of its own: it references
  # Dexpace::Pipeline::Stages by that name and uses Dexpace::Pipeline::Cursor unchanged. PIPE-28's
  # "the two runtimes MUST NOT each re-derive ordering independently" is satisfied by there being
  # nothing to keep in sync -- what differs is one private driver, which arrives as a constructor
  # argument from Builder#build_async (P4-30). Flat, not Dexpace::Pipeline::Async (P4-36):
  # Pipeline's namespace also holds the three things this runtime SHARES rather than mirrors, and
  # a variant-of reading is the opposite of PIPE-28's; phase 2 chose the same shape for
  # Dexpace::AsyncTransport.
  #
  # PIPE-29 and PIPE-30 are the driver's: a step's synchronous StandardError becomes a failed
  # future, so one step's mistake cannot break the async contract, and the fatal family --
  # ScriptError included, so a step that lazily requires something absent raises a LoadError out
  # of #call -- propagates synchronously. A step's future comes back as itself, never re-wrapped.
  #
  # **PIPE-32, and this paragraph IS the requirement's last clause discharged.** The async
  # standard pipeline MUST NOT follow HTTP redirects at the pipeline layer -- there is no async
  # redirect pillar step -- and "a port MUST document this asymmetry with the sync standard
  # pipeline". The asymmetry: Pipeline.standard installs redirect + retry + instrumentation,
  # while AsyncPipeline.standard installs retry + instrumentation only and takes an explicit
  # `redirect: :unsupported` argument -- REQUIRED, and refusing every other value -- so the
  # absence is visible at the call site. Both constructors exist since phase 6b's Task 13a, so
  # the clause holds substantively: the async standard pipeline has no step at REDIRECT and a
  # 3xx surfaces to the caller verbatim (REDIR-25). What phase 4c deliberately did NOT do, and
  # phase 6b keeps, is make Stages::REDIRECT un-installable on the async path: PIPE-28 requires
  # the identical staging policy in both runtimes, and a builder that rejected a REDIRECT step
  # for #build_async and accepted it for #build would be two policies. PIPE-32 constrains the
  # PRESET, not the runtime.
  #
  # PIPE-34's bridge is phase 2's Dexpace::AsyncTransport.sync_over(async_pipeline), not a method
  # here (R13, P4-35): a built async pipeline answers #call(request, options, cancellation) with a
  # future, which is exactly what that bridge takes, and the wait it performs is phase 2's
  # Future#value(cancellation:) -- this phase writes no wait. Not Object#freeze'd, for the reason
  # Dexpace::Pipeline is not: PIPE-27's latch writes an ivar.
  class AsyncPipeline
    include Dexpace::Closeable

    # @return [Array<Dexpace::Pipeline::Entry>] the stage-annotated view, frozen, the same object
    #   every call (PIPE-25)
    attr_reader :entries
    # @return [Array] the read-only ordered view of the steps, frozen (PIPE-25)
    attr_reader :steps
    # @return [#call] the terminal async transport; public because Builder.flattening reads it
    attr_reader :transport

    private_class_method :new

    # PIPE-39's step-less shape, async form: PIPE-9's empty branch behind a name. The second
    # shape is .standard, below.
    #
    # @param transport [#call] an async transport
    # @return [Dexpace::AsyncPipeline]
    def self.direct(transport) = Pipeline::Builder.new(transport: transport).build_async

    # PIPE-39's second named shape, the async standard pipeline: phase 6a's
    # Resilience::AsyncRetryStep at RETRY and phase 5b's Instrumentation::AsyncStep at LOGGING,
    # installed through Pipeline::Builder#install_preset and through nothing else (phase 4c's
    # R14), and NO step at REDIRECT (PIPE-32, REDIR-25). `redirect:` is a required keyword that
    # admits exactly `:unsupported`: the asymmetry with Pipeline.standard is spelled at the call
    # site rather than left as an absence a reader has to notice (design §5.3). Written by phase
    # 6b's Task 13a, the constructor phase 4c postponed.
    #
    # The keywords are Pipeline.standard's, minus a step for REDIRECT: `over` is an async
    # transport or a Pipeline::Builder holding one (PIPE-24's empty-pillars rule applies to the
    # second form); the retry step is built over `settings:`, `http_tracer_factory:` and
    # `logger:`, the instrumentation step over `logger:`, `level:` and `preview_bytes:`. The
    # async retry step waits through Dexpace::Async.delay, which needs a Fiber.scheduler: with
    # none registered, a POSITIVE backoff fails the returned future with Dexpace::SeamError
    # (never a blocking sleep), while a zero-length delay completes inline -- so a preset built
    # with no scheduler retries only under settings whose delays are zero (6a's P6-54, R2's
    # third route). This constructor takes no scheduler keyword because the step takes none.
    #
    # @param over [#call, Dexpace::Pipeline::Builder] an async transport, or a builder holding one
    # @param redirect [Symbol] `:unsupported`, and nothing else
    # @param settings [Dexpace::Resilience::RetrySettings] the retry step's configuration
    # @param http_tracer_factory [#call, nil] the retry step's OBS-29 tracer factory
    # @param logger [Dexpace::Instrumentation::Logger] shared by both steps
    # @param level [Dexpace::Instrumentation::HTTPLogging] the instrumentation step's level
    # @param preview_bytes [Integer, nil] the body-preview cap, required at the body level
    # @return [Dexpace::AsyncPipeline]
    # @raise [Dexpace::InvalidArgumentError] for any `redirect:` but `:unsupported` (PIPE-32), a
    #   transport that is not one, or a level whose requirements are unmet
    # @raise [Dexpace::PipelineError] when RETRY or LOGGING of `over` is already occupied (PIPE-24)
    def self.standard(over, redirect:, settings: Resilience::RetrySettings.build,
                      http_tracer_factory: nil, logger: Instrumentation::Logger::NULL,
                      level: Instrumentation::HTTPLogging::DEFAULT, preview_bytes: nil)
      given = redirect #: untyped
      unless given == :unsupported
        raise InvalidArgumentError,
              "AsyncPipeline.standard follows no redirects at the pipeline layer (PIPE-32); " \
              "pass redirect: :unsupported, got #{given.inspect}"
      end

      retry_step = if http_tracer_factory.nil? # the family's own no-op default stays private
                     Resilience::AsyncRetryStep.build(settings: settings, logger: logger)
                   else
                     Resilience::AsyncRetryStep.build(settings: settings, logger: logger,
                                                      http_tracer_factory: http_tracer_factory,)
                   end
      entries = [
        Pipeline::Entry.build(stage: Pipeline::Stages::RETRY, step: retry_step),
        Pipeline::Entry.build(stage: Pipeline::Stages::LOGGING,
                              step: Instrumentation::AsyncStep.build(
                                logger: logger, level: level, preview_bytes: preview_bytes,
                              ),),
      ]
      builder = over.is_a?(Pipeline::Builder) ? over : Pipeline::Builder.new(transport: over)
      builder.install_preset(entries).build_async
    end

    # PIPE-31's terminal response-mapping operator (P4-38): a class method over the pivot rather
    # than a #call-with-handler overload, because PIPE-26 requires #call to stay exactly the
    # transport SPI's three positional parameters -- and because this way the four clauses are
    # testable against a bare Completer with no pipeline, transport or fake in sight.
    #
    # Written over phase 2's Future#then, which already carries three of the four clauses: a
    # failure is forwarded as the SAME object (this port never wraps, so there is nothing to
    # unwrap), a cancellation of the mapped future cancels the source with its reason, and a
    # raising handler fails the derived future instead of escaping the settling thread. What
    # this operator adds is the close: on success the handler is applied and THEN the response is
    # closed, and on handler failure it is closed anyway -- both in one `ensure`, and the
    # idempotent double close PIPE-31 tolerates is a property of phase 3's latch, not of this
    # operator. "Close any response that accompanies a failure" has exactly one reachable case,
    # the handler raising over a response the source delivered: Settlement.failure carries an
    # error and no response, so a source failure has nothing to close.
    #
    # @param source [Dexpace::Async::Future] the send's future
    # @yieldparam response [Dexpace::Response] open, closed as soon as the block returns or raises
    # @yieldreturn [Object] what the mapped future settles with; nil fails it, as Future#then says
    # @return [Dexpace::Async::Future]
    # @raise [Dexpace::InvalidArgumentError] without a block, or over a non-future
    def self.map_response(source)
      raise InvalidArgumentError, "map_response requires a block" unless block_given?
      unless source.is_a?(Dexpace::Async::Future)
        raise InvalidArgumentError, "map_response takes a Future, got #{source.class}"
      end

      source.then do |response|
        yield response
      ensure
        Dexpace.close_quietly(response)
      end
    end

    # Only Builder reaches this; see Pipeline#initialize.
    def initialize(entries:, transport:, driver_class:)
      initialize_closeable(owned: false)
      @entries = entries.dup.freeze
      @steps = @entries.map(&:step).freeze
      @transport = transport
      @driver_class = driver_class
    end

    # The async send: PIPE-9's empty branch and PIPE-10's cursor branch, as Pipeline#call, with
    # the driver normalising both (PIPE-30 names the empty-pipeline dispatch explicitly). Cursor
    # is reached qualified because this class's cref does not include Dexpace::Pipeline; there is
    # exactly one Cursor class and both runtimes use it (P4-30).
    #
    # `bundle:` is phase 6a's widening, as on Pipeline#call: the empty branch dispatches with
    # no cursor and therefore carries no bundle, which is PIPE-9's own shape.
    #
    # @param request [Dexpace::Request]
    # @param options [Dexpace::RequestOptions]
    # @param cancellation [Dexpace::Cancellation]
    # @param bundle [Dexpace::Instrumentation::Bundle] the per-call correlation bundle
    # @return [Dexpace::Async::Future]
    def call(request, options = RequestOptions::EMPTY, cancellation = Cancellation.none,
             bundle: Instrumentation::Bundle::NONE)
      driver = @driver_class.new(self)
      return driver.dispatch(request, options, cancellation) if @entries.empty?

      Pipeline::Cursor.build(drive: driver, request: request, options: options,
                             cancellation: cancellation, bundle: bundle,).call(request)
    end
  end
end
