# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "step"
require_relative "diagnostics"
require_relative "../async/future"

module Dexpace
  module Instrumentation
    # OBS-34, OBS-36, OBS-39 and OBS-20 on the async runtime: the same step over 4c's
    # _AsyncStep, sharing Step's private Emitter, so the two paths cannot drift (OBS-17,
    # P5-34). Subclassing inherits .build unchanged, so both steps take the same keywords by
    # construction, and `new` stays private through the singleton chain.
    #
    # Two things differ from the sync step, and both follow from the future settling later, on
    # whatever thread or fiber settles it (phase 2's #on_settle contract). First, the scope --
    # the current-span slot and the two correlation keys 5c's Tracing.correlate pushes -- is
    # closed at the end of the synchronous head, on the calling fiber, and not in the
    # settlement callback (P5-93): Scope#close writes the CURRENT fiber's storage, so closing it
    # on a pool thread would restore the caller's prior values into the wrong fiber and leave
    # the caller's fiber carrying a dead request's keys. What the settlement side needs of the
    # caller's diagnostic context it gets through OBS-24's bridge: the context is captured
    # once the head is done and reinstalled around the response or failure event with
    # Diagnostics.with, the case that bridge was shaped for. The span itself stays open until
    # settlement, where #finish and the two instruments run.
    #
    # Second, the returned future. Below the body level the step observes: it registers
    # #on_settle on the future the chain returned and returns THAT future, so no second future
    # exists and PIPE's chain is untouched. At the body level the step must TRANSFORM: OBS-36's
    # "a body larger than the cap MUST still stream in full to the caller" is only true if the
    # caller receives the ResponseLoggingBody-wrapped response, whose over-cap regime replays
    # the captured prefix and continues from the live tail -- reading a preview off a wrapper
    # the caller never sees would consume the caller's bytes. So at the body level the step
    # derives through Future#then, which 4c added over phase 2's pivot: a failure is forwarded
    # as the same object, a cancellation as a cancellation, and cancelling the derived future
    # cancels the source (P5-94). The design's verified fact 13 predates #then.
    #
    # OBS-20's asymmetry has a sharper edge here, stated because nothing else states it: the
    # settlement work runs on the settling thread, so a meter that throws -- which OBS-20 says
    # is not wrapped -- propagates into the PRODUCER, into whoever settled the future, and not
    # into the caller; when the future settled inside the head, the producer IS the caller and
    # the raise fails the request, as it does on the sync path. The log emissions are contained
    # on both paths and have no such consequence. Two things keep that true at every level
    # (P5-109, review round 2's R2-3). The settlement work is registered on the SOURCE future
    # at every level, never on the derived one: Future#then runs the derived future's
    # settlement inside its own `rescue`, so a meter raising from a derived future's callback
    # would fail a future that had just been fulfilled -- a no-op -- and vanish. And the span is
    # finished and the instruments recorded by exactly one side: the head's `ensure` when the
    # head raised before the chain handed back its future, and the settlement callback
    # otherwise, so a settlement that ran inline on an already-settled future and raised does
    # not meet a second finish in the head's `ensure`.
    class AsyncStep < Step
      # What the settlement side needs of the head: the request as sent, the start time, the
      # bridged diagnostic context (nil when nothing is logged) and the open span. A private
      # value carried through the callbacks, because a callback takes one argument.
      class Pending < Data.define(:request, :started, :snapshot, :span)
      end
      private_constant :Pending

      # Drives the chain once and returns a future. See the class comment for what happens on
      # each side of the settlement.
      #
      # @param request [Dexpace::Request]
      # @param cursor [Dexpace::Pipeline::Cursor]
      # @return [Dexpace::Async::Future] the chain's future below the body level; a derived one
      #   carrying the wrapped response at it
      def call(request, cursor)
        future, pending = head(request, cursor)
        attach(future, pending)
      end

      private

      # The synchronous head, from the span's start to the chain's future, its scope closed on
      # the calling fiber whichever way it ends (P5-93). A head that raised before the chain
      # handed back its future -- `pending` still nil -- tears the span down here too, unwrapped
      # (OBS-20, OBS-30); one that did not leaves that to the settlement side alone, so the two
      # sides cannot both run it (P5-109).
      #
      # @return [Array] the future and the Pending the settlement side needs
      def head(request, cursor)
        started = @clock.monotonic
        bundle = cursor.bundle
        span = open_span(request, bundle)
        scope = Tracing.correlate(span, bundle)
        pending = nil #: Pending?
        begin
          request = prepare(request)
          future = cursor.call(request)
          pending = Pending.new(request: request, started: started, span: span,
                                snapshot: logged? ? Diagnostics.capture : nil,)
          [future, pending] #: [Dexpace::Async::Future, Pending]
        ensure
          scope.close
          finish(span, started) if pending.nil?
        end
      end

      # The settlement side: the response or failure event under the bridged context, then the
      # span's finish and the two instruments, unwrapped -- registered on the SOURCE future at
      # both levels, outside Future#then's rescue (P5-109). At the body level the derivation
      # comes first, so the source's callbacks run in the order the sync path emits: the
      # response event and the derived future's fulfilment, then the finish; a meter that raises
      # there is collected by Hooks.notify, which still runs every later callback, and re-raised
      # into the producer once the list has run.
      def attach(future, pending)
        if body?
          derived = future.then { |response| settle_response(pending, wrap_response(response)) }
          future.on_settle { |settlement| settle(pending, settlement) }
          derived
        else
          future.on_settle do |settlement|
            settle_response(pending, settlement.response) if settlement.success?
            settle(pending, settlement)
          end
        end
      end

      # The response event, bridged; returns the response so Future#then settles with it.
      def settle_response(pending, response)
        bridged(pending.snapshot) { log_response(pending.request, response, pending.started) }
        response
      end

      # The failure event, bridged, then the tracer and meter work.
      def settle(pending, settlement)
        error = settlement.error
        unless error.nil?
          bridged(pending.snapshot) { log_failure(pending.request, error, pending.started) }
        end
        finish(pending.span, pending.started)
      end

      # OBS-24's bridge around a log emission; nothing to bridge when nothing is logged.
      def bridged(snapshot, &)
        return yield if snapshot.nil?

        Diagnostics.with(snapshot, &)
      end
    end
  end
end
