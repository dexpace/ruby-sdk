# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "closeable"
require_relative "http/request_options"
require_relative "cancellation"

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
    # PIPE-9's empty pipeline behind a name a caller can find. The second, Pipeline.standard, is
    # postponed to phase 6 (6b, Task 13a): the redirect and retry families are phase 6's and the
    # instrumentation step is phase 5's, and a constructor named for defaults it cannot install
    # is worse than its absence. Builder#install_preset is the mechanism it will be written over.
    #
    # @param transport [#call] the terminal hop
    # @return [Dexpace::Pipeline]
    def self.direct(transport) = Builder.new(transport: transport).build

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
    # @param request [Dexpace::Request]
    # @param options [Dexpace::RequestOptions] the caller's per-call options, threaded unchanged
    # @param cancellation [Dexpace::Cancellation]
    # @return [Dexpace::Response]
    def call(request, options = RequestOptions::EMPTY, cancellation = Cancellation.none)
      return @transport.call(request, options, cancellation) if @entries.empty?

      Cursor.build(drive: @driver_class.new(self), request: request, options: options,
                   cancellation: cancellation,).call(request)
    end
  end
end
