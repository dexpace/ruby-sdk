# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "step"
require_relative "../registry"
require_relative "../async/completer"
require_relative "../async/future"
require_relative "../error/cancelled_error"

module Dexpace
  module Auth
    # AUTH-27–AUTH-38 on the async runtime: the same step over 4c's _AsyncStep, sharing Step's
    # private helpers -- the cross-origin read, the HTTPS guard, the 401 tests and AUTH-31's
    # one replayability predicate -- so the two paths cannot drift (spec-forced boundary 13).
    # Subclassing inherits .build, so both steps take the same keywords; only the stamper shape
    # widens, to anything answering `#stamp(request) -> Future` (AsyncBearerStamper) beside
    # `#call(request) -> Request` (every other stamper, adapted into a settled future here).
    #
    # The whole body runs inside one Completer-backed frame (6c's R12): the HTTPS guard, the
    # stamp, the drive, the bearer branch and the challenge hook all settle the ONE returned
    # future, and every raise inside the frame -- on the calling fiber or in a settlement
    # callback on whatever thread settles a future -- fails it rather than propagating. That is
    # what makes AUTH-38's SHOULD unconditional here: not a per-error-type special case and not
    # a scheduler-presence branch, since nothing in this class waits, delays or calls #value.
    # AUTH-32's three clauses are all real on this path: a hook that raises synchronously, one
    # whose returned future fails, and one that returns something that is not a request all
    # leave the open 401 closed behind them, the close failure on the error's trail.
    #
    # AUTH-36 with AUTH-37's last clause: after a successful eviction the retry is stamped by
    # #stamp_fresh, which awaits a genuinely fresh fetch; after a failed one (another request
    # already refreshed the token) by #stamp, which reuses it. Cancelling the returned future
    # cancels whichever inner future is in flight (SEAM-18), and an inner cancellation is
    # forwarded as a cancellation, never as a plain failure.
    class AsyncStep < Step # rubocop:disable Metrics/ClassLength -- the sync step's one #call, written as the continuations one Completer frame needs; see the class comment
      # One 401 exchange's four references, carried through the callbacks as one argument.
      class Exchange < ::Data.define(:stamped, :response, :cursor, :completer)
      end
      private_constant :Exchange

      # The stamper shapes this runtime drives: `#stamp -> Future` or `#call -> Request`.
      def self.stamper!(stamper)
        return if Registry.callable?(stamper, arity: 1)
        return if stamper.respond_to?(:stamp)

        raise InvalidArgumentError, "stamper must answer #stamp(request) or #call(request)"
      end
      private_class_method :stamper!

      # @param request [Dexpace::Request]
      # @param cursor [Dexpace::Pipeline::Cursor]
      # @return [Dexpace::Async::Future] settling with the response, or failing
      def call(request, cursor)
        completer = Dexpace::Async::Completer.new
        guarded(completer) do
          if cross_origin?(cursor) # AUTH-29: no guard, no stamp, still a fork (P4-39)
            chain_into(cursor.fork.call(request), completer)
          else
            enforce_https!(request) # AUTH-28, AUTH-38: a raise here fails the future
            observe(stamp_async(request), completer) do |settlement|
              drive(settlement, cursor, completer)
            end
          end
        end
        completer.future
      end

      private

      # AUTH-38's frame: every StandardError inside settles the future as a failure.
      def guarded(completer)
        yield
      rescue ::StandardError => error
        completer.fail(error)
      end

      # A stamper that answers #stamp is async already; every other is adapted, and a raise
      # from it lands in the caller's guarded frame.
      def stamp_async(request)
        return @stamper.stamp(request) if @stamper.respond_to?(:stamp)

        settled(@stamper.call(request))
      end

      def settled(value)
        completer = Dexpace::Async::Completer.new
        completer.fulfil(value)
        completer.future
      end

      # Watch one inner future from the frame: its settlement is handled inside the guarded
      # frame, and cancelling the frame's future cancels it (SEAM-18, both ways).
      def observe(future, completer)
        completer.on_cancel { |reason| future.cancel(reason) }
        future.on_settle { |settlement| guarded(completer) { yield settlement } }
      end

      # Forward one future's settlement into the frame's completer as it is.
      def chain_into(future, completer)
        observe(future, completer) do |settlement|
          if settlement.success?
            completer.fulfil(settlement.response)
          else
            forward_failure(settlement, completer)
          end
        end
      end

      # A cancellation stays a cancellation one link down; a failure is the same object.
      def forward_failure(settlement, completer)
        error = settlement.error
        return if error.nil? # a failed settlement always carries one (Settlement's own rule)

        if settlement.cancelled && error.is_a?(Dexpace::CancelledError)
          completer.request_cancel(error.reason)
        else
          completer.fail(error)
        end
      end

      # The stamped request drives a fresh fork; its settlement is handled below.
      def drive(settlement, cursor, completer)
        return forward_failure(settlement, completer) unless settlement.success?

        stamped = settlement.response
        observe(cursor.fork.call(stamped), completer) do |driven|
          if driven.success?
            handle(Exchange.new(stamped: stamped, response: driven.response, cursor: cursor,
                                completer: completer,))
          else
            forward_failure(driven, completer)
          end
        end
      end

      # The sync step's post-drive logic over futures: pass-through, AUTH-33, AUTH-36, AUTH-30.
      def handle(exchange)
        response = exchange.response
        return exchange.completer.fulfil(response) unless unauthorized?(response)

        challenge = challenge_header(response)
        return exchange.completer.fulfil(response) if challenge.nil?
        return bearer_retry_async(exchange) if bearer_retry?(challenge, exchange.stamped)

        replay_async(challenge, exchange)
      end

      # AUTH-36 and AUTH-37's post-eviction clause: evicted → #stamp_fresh; preserved → #stamp.
      def bearer_retry_async(exchange)
        evicted = @stamper.evict_if_matches(rejected_header(exchange.stamped).to_s)
        Dexpace.close_quietly(exchange.response, logger: @logger)
        drive_replacement(restamp(exchange.stamped, evicted), exchange)
      end

      # Once the re-stamp settles, drive the retry through a fresh fork; forward a failure.
      def drive_replacement(restamped, exchange)
        completer = exchange.completer
        observe(restamped, completer) do |settlement|
          if settlement.success?
            chain_into(exchange.cursor.fork.call(settlement.response), completer)
          else
            forward_failure(settlement, completer)
          end
        end
      end

      def restamp(stamped, evicted)
        return @stamper.stamp_fresh(stamped) if evicted && @stamper.respond_to?(:stamp_fresh)

        stamp_async(stamped)
      end

      # AUTH-30 over futures: the hook may answer a request, nil, or a future of either
      # (AUTH-32's "its async future completes exceptionally").
      def replay_async(challenge, exchange)
        result = consult(challenge, exchange.stamped, exchange.response)
        return replace(result, exchange) unless result.is_a?(Dexpace::Async::Future)

        observe(result, exchange.completer) { |settlement| settle_replay(settlement, exchange) }
      end

      # The hook's future settled: its value replayed through the same check and gate as a
      # direct answer, or its failure forwarded with the 401 closed first (AUTH-32).
      def settle_replay(settlement, exchange)
        if settlement.success?
          replace(settled_replacement!(settlement.response, exchange.response), exchange)
        else
          Dexpace.close_quietly(exchange.response, onto: settlement.error)
          forward_failure(settlement, exchange.completer)
        end
      end

      # The hook may hand back a future (P6-78), passed through here and checked once it
      # settles; a direct answer meets the sync check, and a raise closes the 401 (AUTH-32).
      def consult(challenge, stamped, response)
        closing_on_error(response) do
          result = @challenge_hook.call(challenge, stamped, response)
          result.is_a?(Dexpace::Async::Future) ? result : replacement!(result)
        end
      end

      # AUTH-32's third clause once the hook's future settles: a value that is not a request or
      # nil -- a future of a future included -- closes the open 401 before the frame fails the
      # step's future, exactly as the sync #consult does for a direct answer (review round 1).
      def settled_replacement!(replacement, response)
        closing_on_error(response) { replacement!(replacement) }
      end

      # AUTH-30, AUTH-31: nil or a non-replayable replacement surfaces the 401 (unclosed);
      # otherwise the 401 is closed and the replacement driven through a fresh fork once.
      def replace(replacement, exchange)
        if replacement.nil? || !replayable?(replacement)
          return exchange.completer.fulfil(exchange.response)
        end

        Dexpace.close_quietly(exchange.response, logger: @logger)
        chain_into(exchange.cursor.fork.call(replacement), exchange.completer)
      end
    end
  end
end
