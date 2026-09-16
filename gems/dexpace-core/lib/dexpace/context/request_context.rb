# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../context"
require_relative "../context_store"
require_relative "call_key"
require_relative "exchange_context"

module Dexpace
  # The chain's middle, an outgoing request assembled: CTX-2, CTX-16.
  #
  # operation_name is nil or a non-empty frozen String -- CTX-16 gives exactly two states, "a
  # schema-defined operation id such as 'GetUser', or absent", and "" is neither. It is advisory
  # only: it reaches no request, no dispatch decision and, decisively, not the store key, which
  # CallKey.mint derives from the bundle and the counter alone. It is the chain half of SEAM-28's
  # postponed operation identifier; phase 5c, Task 4 is the consumer.
  class RequestContext < Data.define(:bundle, :call_key, :store, :request, :operation_name)
    include Dexpace::Context

    private_class_method :new

    # Off-chain construction (CTX-5), registering nothing (CTX-17).
    #
    # @param bundle [Instrumentation::Bundle] the correlation bundle (CTX-14)
    # @param request [Request] the assembled request
    # @param operation_name [String, nil] CTX-16's advisory operation id, or nil
    # @param call_key [String, nil] an explicit key, or nil to mint one
    # @param store [ContextStore] the store the chain registers in
    # @return [RequestContext]
    def self.build(bundle:, request:, operation_name: nil, call_key: nil,
                   store: ContextStore.default)
      key = call_key.nil? ? CallKey.mint(bundle) : Model.frozen_string(call_key)
      new(
        bundle: bundle, call_key: key, store: store, request: request,
        operation_name: operation_name.nil? ? nil : Model.frozen_string(operation_name),
      )
    end

    # The shared validation, the request, and CTX-16's two-state rule.
    def initialize(bundle:, call_key:, store:, request:, operation_name:)
      validate_context!(bundle: bundle, call_key: call_key, store: store)
      Model.required!("request", request)
      validate_operation_name!(operation_name)

      super
    end

    # -> ExchangeContext. Carries bundle, call_key, store, request and operation_name forward
    # unchanged (CTX-2's "additionally the same request and operationName"), adds the response,
    # and calls store.set, which overwrites the same slot (CTX-3). The source is untouched.
    #
    # @param response [Response] the response that has arrived
    # @return [ExchangeContext] the successor, now the slot's occupant
    def promote_to_exchange(response:)
      ctx = ExchangeContext.build(
        bundle: bundle, call_key: call_key, store: store,
        request: request, operation_name: operation_name, response: response,
      )
      store.set(ctx)
    end
  end
end
