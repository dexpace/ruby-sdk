# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../context"
require_relative "../context_store"
require_relative "call_key"

module Dexpace
  # The chain's terminus, a response arrived: CTX-1, CTX-2. No #promote_* method anywhere in
  # this class -- CTX-1's terminality is the absence, which is the property design §5.4 chose
  # three classes to get. Once registered it is what CTX-19 keeps reachable: the Request and the
  # Response, whose body can pin a connection, stay in the strong map until #close evicts them or
  # the cap does.
  class ExchangeContext < Data.define(
    :bundle, :call_key, :store, :request, :operation_name, :response,
  )
    include Dexpace::Context

    private_class_method :new

    # Off-chain construction (CTX-5), registering nothing (CTX-17).
    #
    # @param bundle [Instrumentation::Bundle] the correlation bundle (CTX-14)
    # @param request [Request] the request that was sent
    # @param response [Response] the response that arrived
    # @param operation_name [String, nil] CTX-16's advisory operation id, or nil
    # @param call_key [String, nil] an explicit key, or nil to mint one
    # @param store [ContextStore] the store the chain registers in
    # @return [ExchangeContext]
    def self.build(bundle:, request:, response:, operation_name: nil, call_key: nil,
                   store: ContextStore.default)
      key = call_key.nil? ? CallKey.mint(bundle) : Model.frozen_string(call_key)
      new(
        bundle: bundle, call_key: key, store: store, request: request,
        operation_name: operation_name.nil? ? nil : Model.frozen_string(operation_name),
        response: response,
      )
    end

    # The shared validation, the two artefacts, and CTX-16's two-state rule.
    def initialize(bundle:, call_key:, store:, request:, operation_name:, response:)
      validate_context!(bundle: bundle, call_key: call_key, store: store)
      Model.required!("request", request)
      Model.required!("response", response)
      if !operation_name.nil? && operation_name.empty?
        raise InvalidArgumentError, "operation_name must not be empty"
      end

      super
    end
  end
end
