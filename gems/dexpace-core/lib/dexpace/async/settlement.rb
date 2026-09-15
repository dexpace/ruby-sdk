# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  # The core-owned async pivot (design §10.3): the canonical, dependency-free future and its
  # write side. Every constant reached from this namespace is written ::-qualified, because once
  # dexpace-async-thread is required a bare `Thread` here is Dexpace::Async::Thread, and core's
  # own suite never requires that gem (verified on 3.2.11 and 4.0.6; Dexpace/QualifiedCoreConstant
  # enforces it).
  module Async
    # What a future settled as. Yielded to #on_settle and returned by Completer#outcome.
    #
    # The cross-field rule -- exactly one of response or error, and cancelled implying error -- is
    # SEAM-16's "MUST NOT complete successfully with a null/absent value" made structural: there is
    # no settled-with-nothing state to construct. It lives in #initialize rather than in a builder
    # because .build is public API, #with routes every derivation through it, and send(:new, ...)
    # reaches the constructor regardless (phase 1's construction rule).
    class Settlement < ::Data.define(:response, :error, :cancelled)
      include Dexpace::Model

      private_class_method :new

      # The validating factory every construction path goes through.
      def self.build(response: nil, error: nil, cancelled: false)
        new(response: response, error: error, cancelled: cancelled)
      end

      # The three shapes SEAM-16 permits, named so a producer cannot construct a fourth by passing
      # the wrong keyword pair to .build.
      def self.success(response) = build(response: response)

      # A failure: the error is delivered to the waiter as the same object.
      def self.failure(error) = build(error: error)

      # A cancellation: a failure whose error is the Dexpace::CancelledError carrying the reason.
      def self.cancellation(error) = build(error: error, cancelled: true)

      def initialize(response:, error:, cancelled:)
        if response.nil? == error.nil?
          raise Dexpace::InvalidArgumentError,
                "a settlement carries exactly one of response or error"
        end
        if cancelled && error.nil?
          raise Dexpace::InvalidArgumentError, "a cancelled settlement carries an error"
        end

        super(response: response, error: error, cancelled: cancelled ? true : false)
      end

      # The one question #on_settle's block actually asks; computing it from two nil checks at
      # every call site is how a caller gets the cross-field rule wrong.
      def success? = error.nil?
    end
  end
end
