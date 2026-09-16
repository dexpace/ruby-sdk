# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"

module Dexpace
  # The module DispatchContext, RequestContext and ExchangeContext all include -- design §5.4's
  # "three distinct Data classes sharing a module", read as a module they include and not as a
  # namespace containing them (P4-1): Dexpace::Context::Request would shadow phase 1's
  # Dexpace::Request for every file inside `module Dexpace; module Context`, which is the hazard
  # Dexpace/QualifiedCoreConstant exists for and cannot express a fix for.
  #
  # CTX-1's terminality -- "the exchange stage is terminal, no method promoting back" -- is
  # enforced by ExchangeContext defining no #promote_* method, not by a guard clause here.
  #
  # #inspect is deliberately NOT overridden, and the consequence is stated rather than
  # discovered: `store` is a Data member, so Data's generated #inspect walks it into the map and
  # prints one level of every OTHER occupant, each with its own request and response. Ruby's
  # recursion guard only elides the second visit to the store itself, so at
  # ContextStore::MAX_TRACKED_CONTEXTS any `p ctx`, any assert_equal failure message and any
  # string interpolating a context becomes a dump of every in-flight call. Phase 1 shipped no
  # #inspect override on Request or Response either, and a redaction-aware rendering is
  # OBS-11..OBS-19's and XCUT-19's, which are phase 5's. What 4a owes instead is that no assertion
  # in its own suite compares whole contexts where a member comparison would do.
  module Context
    include Dexpace::Model

    # CTX-9 (identity-conditional eviction), CTX-10 (a promoted intermediate's close is a no-op)
    # and CTX-18 (double-close is a well-defined no-op) in one line: every clause of all three is a
    # property of ContextStore#release, which this delegates to without a latch (P4-4 -- a frozen
    # Data instance cannot carry one; verified on 3.2.11, 3.4.10 and 4.0.6 that a method on a
    # frozen Data subclass writing an ivar raises FrozenError). Idempotent through the store: the
    # second close finds a different occupant or none.
    #
    # @return [Boolean] whether this context was the slot's occupant and the slot was cleared
    def close
      store.release(self)
    end

    private

    # The construction validation every flavour's #initialize runs before its own fields and
    # before `super`: the two members every flavour carries (SEAM-29's one message form for an
    # absent one), and the store, checked for the two methods a context calls on it rather than
    # for its class -- the narrowest duck type (api-design/88e6bf12), which is what keeps the
    # suite's fake cheap. Private, so it is no part of the NFR-4-locked surface: the design gives
    # Context exactly one public method, #close.
    def validate_context!(bundle:, call_key:, store:)
      Model.required!("bundle", bundle)
      Model.required!("call_key", call_key)
      raise InvalidArgumentError, "call_key must not be empty" if call_key.empty?
      return if store.respond_to?(:set) && store.respond_to?(:release)

      raise InvalidArgumentError, "store must respond to #set and #release"
    end
  end
end
