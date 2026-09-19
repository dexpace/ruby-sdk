# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "closeable"
require_relative "http/request_options"
require_relative "cancellation"
require_relative "instrumentation/bundle"
require_relative "instrumentation/http_logging"
require_relative "instrumentation/logger"
require_relative "instrumentation/step"
require_relative "resilience/retry_settings"
require_relative "resilience/retry_step"
require_relative "redirect/step"
require_relative "error/invalid_argument_error"

module Dexpace
  # The synchronous stage-based execution pipeline (design §5.1): sixteen totally ordered stages
  # holding steps, driven per call by a forward-only cursor with pillar-only forks, over a
  # terminal transport. Built through Builder#build; the nested constants -- Stages, Stage, Step,
  # Entry, Cursor, Builder, TransformStep -- are the subsystem's vocabulary and this class is its
  # runtime.
  #
  # It IS a transport (PIPE-26): #call is exactly the transport SPI's three positional
  # parameters, with and without per-call options, so a built pipeline stands in wherever a
  # transport is expected -- backing a paginator (phase 7), nested as another builder's transport
  # (PIPE-35 NEST), or wrapped by a bridge.
  #
  # **PIPE-33 and PIPE-34 need nothing from this class** (R13, P4-35). Because a pipeline is a
  # transport, phase 2's Dexpace::Transport.async_over(pipeline, executor:) IS the sync-to-async
  # bridge and Dexpace::AsyncTransport.sync_over(async_pipeline) IS the async-to-sync one. This
  # phase ships no second bridge, no executor, and no wait of any kind; a reader looking here for
  # a PIPE-33 object will find none, and that is the answer rather than an omission. Its
  # interrupt clause is design §10.5's unsatisfied MUST.
  #
  # Immutable after construction (PIPE-10): the entry table and the step view are frozen Arrays
  # built once and returned by the same reference every call, the transport is written once,
  # and there is no writer, no #with and no builder handle. NOT Object#freeze'd, deliberately:
  # PIPE-27's close latches, and Closeable#close writes @dexpace_closed, so a frozen runtime
  # would raise FrozenError on the first #close (plan open question 8). Concurrent sends read
  # frozen data with no lock; the per-call state is the cursor, allocated per send.
  #
  # #close is inherited whole and this class defines no #release -- phase 2's shape for both
  # bridges. `owned: false` is what makes Closeable#close flip the latch and return before it
  # would call #release, so PIPE-27's "the pipeline never owns its transport and MUST NOT close
  # it" is a property of the ownership flag rather than of an override someone could delete; a
  # closed pipeline keeps sending, because it released nothing (XCUT-22).
  class Pipeline
    include Dexpace::Closeable

    # @return [Array<Dexpace::Pipeline::Entry>] the stage-annotated view, frozen, the same object
    #   every call (PIPE-25)
    attr_reader :entries
    # @return [Array] the read-only ordered view of the steps, frozen, the same object every call
    #   (PIPE-25)
    attr_reader :steps
    # @return [#call] the terminal transport; public because Builder.flattening must read it
    attr_reader :transport

    private_class_method :new

    # The composition entry point.
    #
    # @param transport [#call] the terminal hop
    # @return [Dexpace::Pipeline::Builder]
    def self.builder(transport:) = Builder.new(transport: transport)

    # PIPE-39's first named shape: a step-less pipeline that forwards directly to a transport --
    # PIPE-9's empty pipeline behind a name a caller can find. The second is .standard, below.
    #
    # @param transport [#call] the terminal hop
    # @return [Dexpace::Pipeline]
    def self.direct(transport) = Builder.new(transport: transport).build

    # PIPE-39's second named shape, the sync standard pipeline: the default resilience pillars
    # over a transport -- phase 6b's Redirect::Step at REDIRECT, phase 6a's Resilience::RetryStep
    # at RETRY and phase 5b's Instrumentation::Step at LOGGING -- installed through
    # Builder#install_preset and through nothing else (phase 4c's R14, P4-34: one installation
    # path, and never a preset that claims defaults it does not install). Written by phase 6b's
    # Task 13a, the constructor phase 4c postponed until all three families existed.
    #
    # `over` is a transport, or a Pipeline::Builder already holding one and possibly other steps:
    # PIPE-24 is what the second form is for -- the preset installs into EMPTY pillars only, and
    # a builder whose REDIRECT, RETRY or LOGGING pillar is already occupied rejects the whole call
    # with nothing installed, while a builder holding steps at other stages keeps them around the
    # preset's. `redirect:` takes a Redirect::Step configured by the caller, or nil for one built
    # over `logger:`; the retry step is built over `settings:`, `http_tracer_factory:` and
    # `logger:`, and the instrumentation step over `logger:`, `level:` and `preview_bytes:`
    # (required at HTTPLogging::BODY, as Instrumentation::Step.build requires it). The async
    # counterpart, AsyncPipeline.standard, installs no redirect step and takes an explicit
    # `redirect: :unsupported` so PIPE-32's asymmetry is visible at the call site.
    #
    # @param over [#call, Dexpace::Pipeline::Builder] the terminal hop, or a builder holding it
    # @param redirect [Dexpace::Redirect::Step, nil] the redirect step; built over `logger:`
    #   when nil
    # @param settings [Dexpace::Resilience::RetrySettings] the retry step's configuration
    # @param http_tracer_factory [#call, nil] the retry step's OBS-29 tracer factory; the
    #   step's own no-op default when nil
    # @param logger [Dexpace::Instrumentation::Logger] shared by the three steps
    # @param level [Dexpace::Instrumentation::HTTPLogging] the instrumentation step's level
    # @param preview_bytes [Integer, nil] the body-preview cap, required at the body level
    # @return [Dexpace::Pipeline]
    # @raise [Dexpace::PipelineError] when a target pillar of `over` is already occupied (PIPE-24)
    # @raise [Dexpace::InvalidArgumentError] for a `redirect:` that is not a Redirect::Step, a
    #   transport that is not one, or a level whose requirements are unmet
    def self.standard(over, redirect: nil, settings: Resilience::RetrySettings.build,
                      http_tracer_factory: nil, logger: Instrumentation::Logger::NULL,
                      level: Instrumentation::HTTPLogging::DEFAULT, preview_bytes: nil)
      retry_step = if http_tracer_factory.nil? # the family's own no-op default stays private
                     Resilience::RetryStep.build(settings: settings, logger: logger)
                   else
                     Resilience::RetryStep.build(settings: settings, logger: logger,
                                                 http_tracer_factory: http_tracer_factory,)
                   end
      entries = [
        Entry.build(stage: Stages::REDIRECT, step: standard_redirect(redirect, logger)),
        Entry.build(stage: Stages::RETRY, step: retry_step),
        Entry.build(stage: Stages::LOGGING,
                    step: Instrumentation::Step.build(logger: logger, level: level,
                                                      preview_bytes: preview_bytes,),),
      ]
      builder = over.is_a?(Builder) ? over : Builder.new(transport: over)
      builder.install_preset(entries).build
    end

    # The preset's redirect step: the caller's, or one built over the preset's logger.
    def self.standard_redirect(redirect, logger)
      return Redirect::Step.build(logger: logger) if redirect.nil?
      return redirect if redirect.is_a?(Redirect::Step)

      raise InvalidArgumentError,
            "redirect: takes a Dexpace::Redirect::Step or nil on the sync standard pipeline, " \
            "got #{redirect.inspect}"
    end
    private_class_method :standard_redirect

    # Only Builder reaches this: `new` is private, and driver_class: is one of the two
    # private_constant drivers, which resolve unqualified inside Builder because it is nested here
    # (plan open question 9).
    def initialize(entries:, transport:, driver_class:)
      initialize_closeable(owned: false)
      @entries = entries.dup.freeze
      @steps = @entries.map(&:step).freeze
      @transport = transport
      @driver_class = driver_class
    end

    # The send. PIPE-9's MUST and its trailing SHOULD in one branch: an empty pipeline has no step
    # to hand a cursor to and therefore no per-call mutable state to share, so PIPE-10's guarantee
    # holds with no cursor allocated at all. There is no reading under which a NON-empty pipeline
    # may skip the cursor (R12).
    #
    # `bundle:` is phase 6a's widening (Task 8): the per-call instrumentation bundle the cursor
    # carries to every step (Cursor#bundle), Bundle::NONE when omitted. An optional keyword
    # beside the transport SPI's three positionals, which Transport.conforms? still accepts, so
    # a Pipeline stays a Dexpace::Transport by the duck type (P4-38's reasoning, widened, P6-51).
    #
    # @param request [Dexpace::Request]
    # @param options [Dexpace::RequestOptions] the caller's per-call options, threaded unchanged
    # @param cancellation [Dexpace::Cancellation]
    # @param bundle [Dexpace::Instrumentation::Bundle] the per-call correlation bundle
    # @return [Dexpace::Response]
    def call(request, options = RequestOptions::EMPTY, cancellation = Cancellation.none,
             bundle: Instrumentation::Bundle::NONE)
      return @transport.call(request, options, cancellation) if @entries.empty?

      Cursor.build(drive: @driver_class.new(self), request: request, options: options,
                   cancellation: cancellation, bundle: bundle,).call(request)
    end
  end
end
