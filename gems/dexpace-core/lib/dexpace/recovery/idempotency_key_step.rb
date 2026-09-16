# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "transform"
require_relative "../error/invalid_argument_error"
require_relative "../http/header_name"
require_relative "../http/method"
require_relative "../http/request"
require_relative "../registry"

module Dexpace
  module Recovery
    # RECOV-32: the idempotency-key request transform. Stamps a configured header on a request
    # whose method is in a configured set -- the non-idempotent write methods POST, PUT and PATCH
    # by default -- and passes every other method through by identity.
    #
    # Two modes. In :respect_existing, the default, a request already carrying the header is
    # returned by identity and the strategy is NOT invoked: design §5.1's own emphasis, because a
    # strategy invoked on every pass burns a fresh key per redirect hop and the server sees a
    # different operation each time. In :overwrite the strategy's result replaces every existing
    # value. In both modes the strategy runs at most once per applicable request.
    #
    # The strategy is any #call(request) -> String; core ships no default, because a default
    # would have to mint a UUID and `securerandom` being on the require allowlist is not a
    # licence to pick a caller's key format. Its result goes through phase 1's outbound header
    # validation, so a value that cannot be carried on the wire is refused rather than smuggled.
    #
    # A :request transform (R8): installs into a RequestChain as itself, and into phase 4c's
    # pipeline through its generic wrapper. Holds no per-call state (RECOV-14) -- the method set
    # is copied and frozen at construction and every other member is a frozen value.
    class IdempotencyKeyStep
      include Transform

      # RECOV-32's default set. Private, because P4-24 fixes the public constants this phase
      # adds and this is not one of them; a private constant is still reachable by its bare
      # name from inside the class, which is where the default is evaluated.
      DEFAULT_METHODS = [Method::POST, Method::PUT, Method::PATCH].freeze
      private_constant :DEFAULT_METHODS

      MODES = %i[respect_existing overwrite].freeze
      private_constant :MODES

      # @return [String] the header name, as configured
      attr_reader :header

      # @return [#call] the key strategy, `#call(request) -> String`
      attr_reader :strategy

      # @return [Array<Dexpace::Method>] the frozen method set
      attr_reader :methods

      # @return [Symbol] :respect_existing or :overwrite
      attr_reader :mode

      private_class_method :new

      # The validating factory. The header name is validated through phase 1's HeaderName here,
      # at construction, so a name that cannot be sent is refused before any request meets it.
      #
      # @param header [String] the header to stamp
      # @param strategy [#call] `#call(request) -> String`
      # @param methods [Array<Dexpace::Method>] the applicable methods
      # @param mode [Symbol] :respect_existing or :overwrite
      # @return [Dexpace::Recovery::IdempotencyKeyStep]
      # @raise [Dexpace::InvalidArgumentError] for an invalid name, a non-callable strategy, a
      #   method set holding anything but Dexpace::Method values, or an unknown mode
      def self.build(header:, strategy:, methods: DEFAULT_METHODS, mode: :respect_existing)
        name = HeaderName.of(Model.required!("header", header)).original
        Model.required!("strategy", strategy)
        unless Registry.callable?(strategy, arity: 1)
          raise InvalidArgumentError, "strategy must respond to #call(request)"
        end
        unless methods.is_a?(::Array) && methods.all?(Method)
          raise InvalidArgumentError, "methods must be an Array of Dexpace::Method"
        end
        unless MODES.include?(mode)
          raise InvalidArgumentError, "mode must be :respect_existing or :overwrite"
        end

        new(header: name, strategy: strategy, methods: methods.dup.freeze, mode: mode)
      end

      def initialize(header:, strategy:, methods:, mode:)
        @header = header
        @strategy = strategy
        @methods = methods
        @mode = mode
      end

      # @return [Symbol] :request
      def phase = :request

      # @param request [Dexpace::Request]
      # @return [Dexpace::Request] the same object when nothing applies, a copy otherwise
      def apply(request)
        return request unless @methods.include?(request.method)
        return request if @mode == :respect_existing && request.headers.include?(@header)

        key = @strategy.call(request)
        builder = request.headers.new_builder
        @mode == :overwrite ? builder.set(@header, key) : builder.add(@header, key)
        request.with(headers: builder.build)
      end
    end
  end
end
