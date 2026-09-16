# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../context"
require_relative "../context_store"
require_relative "call_key"
require_relative "request_context"

module Dexpace
  # The chain's head, before any request exists: CTX-1, CTX-2, CTX-5, CTX-17.
  #
  # Every flavour carries `store` as a member so #close needs no argument and no ambient lookup,
  # and CTX-9's identity eviction has an unambiguous target. `store` falls through to identity in
  # the generated ==, eql? and hash (ContextStore defines neither), which is what two contexts
  # sharing one process-wide store want; a pinned call_key therefore restores value equality only
  # between contexts built against the same store object. The one Data-generated method it makes
  # expensive is #inspect, stated at Dexpace::Context.
  #
  # `bundle:` is required and never defaulted to Bundle::NONE: CTX-15 requires the no-op bundle to
  # be available as the default, which Bundle::NONE is, not that a context silently acquire it --
  # defaulting it would make an untraced chain and a chain whose tracing was dropped by accident
  # indistinguishable at the construction site as well as downstream.
  class DispatchContext < Data.define(:bundle, :call_key, :store)
    include Dexpace::Context

    private_class_method :new

    # CTX-5's off-chain construction, with its explicit-key affordance and its minting default:
    # `call_key:` pins a shared key when a caller needs value equality across contexts (and is
    # frozen without aliasing the caller's String), and absent it, CallKey mints a call-unique
    # one. Construction registers NOTHING (CTX-17): the first store entry a chain ever has is
    # installed by the first promotion, below.
    #
    # @param bundle [Instrumentation::Bundle] the correlation bundle (CTX-14)
    # @param call_key [String, nil] an explicit key, or nil to mint one
    # @param store [ContextStore] the store the chain registers in; the process-wide one by
    #   default, which construction only reads
    # @return [DispatchContext]
    def self.build(bundle:, call_key: nil, store: ContextStore.default)
      key = call_key.nil? ? CallKey.mint(bundle) : Model.frozen_string(call_key)
      new(bundle: bundle, call_key: key, store: store)
    end

    # The shared validation, then Data's own construction.
    def initialize(bundle:, call_key:, store:)
      validate_context!(bundle: bundle, call_key: call_key, store: store)

      super
    end

    # -> RequestContext. Carries forward the SAME bundle object, the SAME call_key and the SAME
    # store (CTX-2, CTX-3), adds exactly the one new artefact, introduces operation_name as an
    # argument exactly as CTX-2 says ("the dispatch context has no operationName field, so it is
    # not 'carried forward'"), and registers the successor with store.set before returning it --
    # the first store entry the chain ever has (CTX-17). The source is untouched.
    #
    # @param request [Request] the outgoing request that has been assembled
    # @param operation_name [String, nil] CTX-16's advisory operation id, or nil
    # @return [RequestContext] the successor, already registered
    def promote_to_request(request:, operation_name: nil)
      ctx = RequestContext.build(
        bundle: bundle, call_key: call_key, store: store,
        request: request, operation_name: operation_name,
      )
      store.set(ctx)
    end
  end
end
