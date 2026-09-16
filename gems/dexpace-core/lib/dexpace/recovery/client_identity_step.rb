# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "transform"
require_relative "../error/invalid_argument_error"
require_relative "../http/header_name"
require_relative "../http/request"

module Dexpace
  module Recovery
    # RECOV-33: the client-identity request transform. Composes its configured tokens into one
    # space-separated line and reconciles it with whatever the request already carries, by mode.
    #
    # In :append, the default, the line goes after the FIRST existing value -- "host/3.0 sdk/1.0"
    # -- and every other pre-existing value survives in order, which is why the reconciliation
    # rebuilds the value list rather than calling Headers::Builder#set, which replaces the whole
    # list; when the header is absent the line becomes its sole value. In :replace, every
    # existing value is overwritten. Two halves of the requirement are easy to miss and are
    # stated here because each has its own test: an empty token list, or one whose tokens are all
    # blank, makes the step a no-op that returns the request by identity and never emits a blank
    # header; and in :append an empty first existing value is treated as absent, so no leading
    # space is emitted.
    #
    # Tokens are stripped and blank ones dropped before joining, so "a single space-separated
    # value" is literally single-spaced whatever the caller's list looked like. The line goes
    # through phase 1's outbound header validation, so a token that cannot be carried on the wire
    # is refused rather than smuggled. A :request transform (R8) holding no per-call state
    # (RECOV-14): the token list is copied and frozen at construction.
    class ClientIdentityStep
      include Transform

      MODES = %i[append replace].freeze
      private_constant :MODES

      # @return [String] the header name, as configured
      attr_reader :header

      # @return [Array<String>] the frozen token list
      attr_reader :tokens

      # @return [Symbol] :append or :replace
      attr_reader :mode

      private_class_method :new

      # The validating factory. The header name is validated through phase 1's HeaderName here,
      # at construction, so a name that cannot be sent is refused before any request meets it.
      #
      # @param header [String] the header to compose into
      # @param tokens [Array<String>] the identity tokens, joined with single spaces
      # @param mode [Symbol] :append or :replace
      # @return [Dexpace::Recovery::ClientIdentityStep]
      # @raise [Dexpace::InvalidArgumentError] for an invalid name, a token list that is not an
      #   Array of Strings, or an unknown mode
      def self.build(header:, tokens:, mode: :append)
        name = HeaderName.of(Model.required!("header", header)).original
        Model.required!("tokens", tokens)
        unless tokens.is_a?(::Array) && tokens.all?(::String)
          raise InvalidArgumentError, "tokens must be an Array of Strings"
        end
        raise InvalidArgumentError, "mode must be :append or :replace" unless MODES.include?(mode)

        new(header: name, tokens: tokens.map(&:freeze).freeze, mode: mode)
      end

      def initialize(header:, tokens:, mode:)
        @header = header
        @tokens = tokens
        @mode = mode
      end

      # @return [Symbol] :request
      def phase = :request

      # @param request [Dexpace::Request]
      # @return [Dexpace::Request] the same object when the line is blank, a copy otherwise
      def apply(request)
        line = @tokens.map(&:strip).reject(&:empty?).join(" ")
        return request if line.empty?

        existing = request.headers[@header]
        builder = request.headers.new_builder
        if @mode == :replace || existing.nil?
          builder.set(@header, line)
        else
          reconcile(builder, existing, line)
        end
        request.with(headers: builder.build)
      end

      private

      # :append against a non-empty existing list: the line after the first value, every other
      # value kept in order, and an empty first value treated as absent.
      def reconcile(builder, existing, line)
        first = existing.first.to_s
        builder.set(@header, first.strip.empty? ? line : "#{first} #{line}")
        existing.drop(1).each { |value| builder.add(@header, value) }
      end
    end
  end
end
