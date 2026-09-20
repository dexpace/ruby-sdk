# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../page"
require_relative "../model"
require_relative "../cancellation"
require_relative "../closeable"
require_relative "../async/completer"
require_relative "../async/future"
require_relative "../error/cancelled_error"
require_relative "../error/invalid_argument_error"
require_relative "../error/seam_error"
require_relative "../http/request"
require_relative "../http/request_options"
require_relative "closing"

module Dexpace
  class Page
    # The non-blocking pagination engine (PAGE-25 through PAGE-33): the same frozen configuration
    # as Paginator plus an optional executor, driving fetch, parse, delivery and re-arm inside the
    # async completion graph through phase 2's Future#on_settle, with no thread blocking on a page.
    # Two walk methods over one pump: #walk delivers items serially, #walk_pages delivers whole
    # live pages -- PAGE-1's two views are required of the engine, not of the blocking one, and
    # PAGE-27 names the page-level drain in as many words.
    #
    # R9, as built. This engine calls no wait of any kind -- not Clock#sleep, not Async.delay --
    # because no async PAGE requirement computes or requests a delay, so phase 5a's no-scheduler
    # SeamError is unreachable from here. With no executor the driver is a callback pump: whoever
    # settles the transport's future drives the next page, on that thread or fiber, which is
    # PAGE-29's stated default; no thread is created, no pool held, no Fiber.scheduler consulted.
    # With an executor -- a caller-supplied object answering `#post { ... }`, the one-method duck
    # type, phase 8's dexpace-async-thread being the first real one -- the whole driver runs on it:
    # the first dispatch and every settlement's continuation are posted, so every consumer
    # invocation happens on the executor and a blocking consumer never ties up a transport
    # callback thread (PAGE-29). A rejecting #post fails the walk with the rejection and closes the
    # response it was carrying (PAGE-30); a rejecting first post fails the walk before any exchange.
    #
    # PAGE-31: the pump is a re-arm-flag trampoline in 6a's AsyncRetryStep image, never a callback
    # that calls the next page: Future#on_settle runs its block INLINE on an already-settled future,
    # so every scripted transport and every synchronously-answering adapter settles inline, and a
    # pump that re-entered itself from the callback overflowed at ~2,600 pages through the real
    # Completer on every interpreter. A settlement that arrives while the loop is running flips a
    # flag under the pump's mutex -- held across the flip only, never across a dispatch, a parse, a
    # consumer call or a close -- and the running loop picks the next page up; one that arrives
    # later, on another thread, starts the loop afresh on a fresh stack. Every callback body is
    # total: a StandardError fails the walk's future, a fatal-family error fails it and propagates,
    # because a raising on_settle block would otherwise escape onto the settling thread through
    # Hooks.notify's re-raise.
    #
    # The returned future settles with the number of pages delivered -- an Integer, never nil,
    # because a Settlement carries exactly one of response or error and a nil success cannot be
    # constructed (SEAM-16; P7-109) -- or fails with the ORIGINAL cause of a consumer throw, a
    # transport failure, a parse failure or an eager transport raise, unwrapped (PAGE-28); a
    # cancellation from either side settles it as a cancellation.
    class AsyncPaginator < ::Data.define(:transport, :template, :strategy, :cap, :options,
                                         :executor,)
      include Model

      private_class_method :new

      # @param transport [#call] `#call(request, options, cancellation) -> Dexpace::Async::Future`
      # @param template [Dexpace::Request] the first page's request
      # @param strategy [_Strategy] a stateless parser answering `#parse(response, template)`
      # @param cap [Numeric] PAGE-9's maximum number of exchanges, strictly positive
      # @param options [Dexpace::RequestOptions] PAGE-36's per-call overrides, applied to every page
      # @param executor [_Executor, nil] PAGE-29's executor mode; nil is the inline default
      # @return [Dexpace::Page::AsyncPaginator] frozen
      # @raise [Dexpace::InvalidArgumentError] when a member is missing or of the wrong shape
      def self.build(transport:, template:, strategy:, cap: ::Float::INFINITY,
                     options: Dexpace::RequestOptions::EMPTY, executor: nil)
        new(transport: transport, template: template, strategy: strategy, cap: cap,
            options: options, executor: executor,)
      end

      def initialize(transport:, template:, strategy:, cap:, options:, executor:)
        validate_engine!(transport, template, strategy)
        unless cap.is_a?(::Numeric) && cap.positive?
          raise InvalidArgumentError,
                "cap must be a strictly positive number, got #{cap.inspect} (PAGE-9)"
        end
        unless Model.required!("options", options).is_a?(Dexpace::RequestOptions)
          raise InvalidArgumentError,
                "options must be a Dexpace::RequestOptions, got #{options.class}"
        end
        unless executor.nil? || executor.respond_to?(:post)
          raise InvalidArgumentError,
                "executor must be nil or respond to #post, got #{executor.class}"
        end

        super
      end

      # The item-level walk: fetches immediately (PAGE-6's carve-out for the non-blocking engine)
      # and delivers every item, one at a time and in server order, to `consumer.call(item)`, never
      # concurrently (PAGE-29). Each page is closed after its items are drained, whether the
      # consumer returned or raised; a throwing close on the success path fails the future, and one
      # after a consumer failure is swallowed so the consumer's cause stays primary (PAGE-32).
      #
      # Cancelling the returned future halts the walk at the next page boundary and cancels the
      # in-flight transport future (PAGE-25, PAGE-26): items already being delivered from the
      # settling page still reach the consumer; a page fetched and parsed but not yet drained is
      # closed quietly and dropped. **The inherent cancellation race, documented as PAGE-33
      # requires:** if the cancel settles the transport's future BEFORE the transport delivers its
      # response, that response never reaches this engine's close path -- releasing it is the
      # transport's responsibility, and for a future built on phase 2's Completer the completer does
      # it (Completer#fulfil on a settled completer closes what it was handed, SEAM-30); conversely
      # a page request already dispatched MAY still complete after the abort, and when it completes
      # successfully this engine closes and discards the response at the page boundary rather than
      # delivering it. A caller's `cancellation:` token is bridged to the same abort and released
      # when the walk settles, so a client-lifetime token retains nothing per walk.
      #
      # @param consumer [#call] `#call(item)`, invoked serially
      # @param cancellation [Dexpace::Cancellation, nil] a caller's token, passed to the transport
      # @return [Dexpace::Async::Future] settles with the number of pages delivered
      # @raise [Dexpace::InvalidArgumentError] when the consumer is not callable or the token is
      #   not a Dexpace::Cancellation
      def walk(consumer, cancellation: nil)
        start(consumer, cancellation, :items)
      end

      # The page-level walk (PAGE-1's async half): the same pump, delivering each live Dexpace::Page
      # once to `consumer.call(page)` BEFORE it is closed, so the consumer sees the open response
      # for the length of its own call; every other rule -- PAGE-25's abort, PAGE-26's boundary,
      # PAGE-27's exactly-once close, PAGE-30's staged-page close, PAGE-32's drain close -- is the
      # one #walk states. PAGE-14's single-use latch has no counterpart here: each call is its own
      # walk, which is PAGE-8.
      #
      # @param consumer [#call] `#call(page)`, invoked serially
      # @param cancellation [Dexpace::Cancellation, nil] a caller's token, passed to the transport
      # @return [Dexpace::Async::Future] settles with the number of pages delivered
      # @raise [Dexpace::InvalidArgumentError] as #walk
      def walk_pages(consumer, cancellation: nil)
        start(consumer, cancellation, :pages)
      end

      private

      def validate_engine!(transport, template, strategy)
        unless Model.required!("transport", transport).respond_to?(:call)
          raise InvalidArgumentError, "transport must respond to #call, got #{transport.class}"
        end
        unless Model.required!("template", template).is_a?(Dexpace::Request)
          raise InvalidArgumentError, "template must be a Dexpace::Request, got #{template.class}"
        end
        return if Model.required!("strategy", strategy).respond_to?(:parse)

        raise InvalidArgumentError, "strategy must respond to #parse, got #{strategy.class}"
      end

      def start(consumer, cancellation, mode)
        unless Model.required!("consumer", consumer).respond_to?(:call)
          raise InvalidArgumentError, "consumer must respond to #call, got #{consumer.class}"
        end
        unless cancellation.nil? || cancellation.is_a?(Dexpace::Cancellation)
          raise InvalidArgumentError,
                "cancellation: takes a Dexpace::Cancellation, got #{cancellation.class}"
        end

        Pump.new(self, consumer, cancellation || Dexpace::Cancellation.none, mode).start
      end

      # The per-walk state and the trampoline (PAGE-31), one instance per walk method call and
      # reachable from nothing but the callbacks it registers: the completer, the next request, the
      # exchange and page counts, the in-flight transport future, and the re-arm protocol's two
      # flags under one mutex. A private_constant with a sig/ mirror. Over the class-length default
      # and deliberately one class, as 6a's Pump is: the re-arm protocol, the fence, the drain and
      # the terminal paths share the completer and the flags, and splitting them across objects
      # would scatter the one invariant the trampoline rests on.
      class Pump # rubocop:disable Metrics/ClassLength -- one per-walk state machine, see above
        # @param paginator [Dexpace::Page::AsyncPaginator]
        # @param consumer [#call]
        # @param cancellation [Dexpace::Cancellation] the token the transport receives
        # @param mode [Symbol] :items or :pages
        def initialize(paginator, consumer, cancellation, mode)
          @paginator = paginator
          @consumer = consumer
          @cancellation = cancellation
          @mode = mode
          @completer = Dexpace::Async::Completer.new
          @next_request = paginator.template #: Dexpace::Request?
          @exchanges = 0
          @pages = 0
          @in_flight = nil #: Dexpace::Async::Future?
          @mutex = ::Thread::Mutex.new
          @running = false
          @rearm = false
        end

        # Arms the two cancellation bridges, submits the first dispatch, and returns the future.
        #
        # @return [Dexpace::Async::Future]
        def start
          guarded do
            @completer.on_cancel { |reason| @in_flight&.cancel(reason) } # PAGE-25
            unless @cancellation.equal?(Dexpace::Cancellation.none)
              subscription = @cancellation.on_cancel { |reason| @completer.request_cancel(reason) }
              @completer.future.on_settle { subscription.detach }
            end
            submit(nil) { resume }
          end
          @completer.future
        end

        private

        # The re-arm protocol (PAGE-31): when a loop is already running on some frame, flip the
        # flag and return -- that loop picks the next page up when its current one returns;
        # otherwise become the loop and keep launching until nothing re-armed it.
        def resume
          return unless claim(:start)

          loop do
            launch
            break unless claim(:continue)
          end
        end

        # :start claims the loop when none runs (else re-arms and answers false); :continue
        # consumes a re-arm (else releases the loop and answers false). The mutex is held across
        # the flag flip only.
        def claim(step)
          @mutex.synchronize do
            if step == :start && @running
              @rearm = true
              false
            elsif step == :start
              @running = true
            elsif @rearm
              @rearm = false
              true
            else
              @running = false
            end
          end
        end

        # One exchange: the same options every time (PAGE-36), the caller's token (or none), and the
        # settlement callback, which hops to the executor when there is one. A transport that raises
        # eagerly or answers something that is not a future is a failed walk (PAGE-28).
        def launch
          return if @completer.settled?

          guarded do
            request = @next_request #: Dexpace::Request
            future = @paginator.transport.call(request, @paginator.options, @cancellation)
            unless future.respond_to?(:on_settle)
              raise InvalidArgumentError,
                    "an async transport must answer a Dexpace::Async::Future, got #{future.class}"
            end

            @exchanges += 1
            @in_flight = future
            future.on_settle { |settlement| deliver(settlement) }
          end
        end

        # The settlement callback, total: inline by default, posted to the executor otherwise, so
        # the driver -- parse, drain, close, re-arm -- runs where PAGE-29 puts it.
        def deliver(settlement)
          guarded { submit(settlement.response) { settled(settlement) } }
        end

        # PAGE-29's one submit site, and PAGE-30's: a rejecting #post fails the walk with the
        # rejection and closes the response it was carrying, quietly (the rejection is primary).
        def submit(response, &)
          executor = @paginator.executor
          return yield if executor.nil?

          begin
            executor.post(&)
          rescue ::StandardError => error
            Dexpace.close_quietly(response, onto: error)
            @completer.fail(error)
          end
          nil
        end

        # A downstream settlement, on whichever thread it lands: a response arriving after the walk
        # settled is closed and discarded (PAGE-33's second half, PAGE-26's drop); a failure is
        # forwarded as the same object and a cancellation as a cancellation (PAGE-28); otherwise
        # parse, build the page, check the boundary again, drain, and advance or finish.
        def settled(settlement)
          response = settlement.response
          guarded do
            next Dexpace.close_quietly(response) if @completer.settled?
            next forward(settlement) unless settlement.error.nil?
            # PAGE-28's null-success clause has a code site although Settlement's own validation
            # makes it unreachable: a null success completion terminates the walk exceptionally.
            next null_success if response.nil?

            page = build_page(response)
            # PAGE-26: staged, undrained, dropped
            next Dexpace.close_quietly(page) if @completer.settled?

            drain(page)
            @pages += 1
            advance
          end
        end

        def null_success
          @completer.fail(Dexpace::SeamError.new("the transport future settled with nothing"))
        end

        # A transport failure completes the walk with the ORIGINAL error object; a transport-side
        # cancellation is forwarded as a cancellation carrying its reason (Future#then's rule).
        def forward(settlement)
          error = settlement.error #: Exception
          if settlement.cancelled && error.is_a?(Dexpace::CancelledError)
            @completer.request_cancel(error.reason)
          else
            @completer.fail(error)
          end
        end

        # PAGE-13 on this path: the response is closed inline on a parse failure and the parse error
        # is primary. The next request is recorded before the page is built.
        def build_page(response)
          info = Closing.parse_or_close(@paginator.strategy, response, @paginator.template)
          @next_request = info.next_request
          Dexpace::Page.build(response: response, items: info.items, next_link: info.next_link,
                              continuation_token: info.continuation_token,)
        end

        # PAGE-32's drain path: the page is released whether the consumer succeeds or throws. On
        # the success path the close is bare and a throwing close propagates into the fence, which
        # fails the future -- the walk terminates instead of hanging. When the consumer already
        # failed the close is quiet, the consumer's cause stays primary and the close error is
        # swallowed; PAGE-26's mid-drain rule holds because nothing here checks the completer
        # between items. Item mode yields each item serially; page mode yields the live page once,
        # before the close (PAGE-1, PAGE-27).
        def drain(page)
          if @mode == :items
            page.items.each { |item| @consumer.call(item) }
          else
            @consumer.call(page)
          end
        rescue ::Exception # rubocop:disable Lint/RescueException -- PAGE-32: the consumer's cause stays primary
          Dexpace.close_quietly(page)
          raise
        else
          page.close
        end

        # After a drained page: terminal when the strategy said end-of-stream (PAGE-4) or the cap is
        # reached (PAGE-9); otherwise re-arm, which the running loop picks up or a fresh one starts.
        def advance
          if @next_request.nil? || @exchanges >= @paginator.cap
            @completer.fulfil(@pages)
          else
            resume
          end
        end

        # The fence every callback body runs inside: a StandardError fails the future -- a raising
        # on_settle block would otherwise escape onto the settling thread through Hooks.notify's
        # re-raise and leave the future hanging -- and a fatal-family error fails it and then
        # propagates unchanged (RECOV-2). Every site closes what it owns before it raises, so the
        # fence closes nothing and cannot double-close.
        def guarded
          yield
        rescue ::StandardError => error
          @completer.fail(error)
        rescue ::Exception => error # rubocop:disable Lint/RescueException -- fail, then re-raise
          @completer.fail(error)
          raise
        end
      end
      private_constant :Pump
    end
  end
end
