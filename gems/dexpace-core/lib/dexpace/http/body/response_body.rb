# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../body"
require_relative "../../closeable"
require_relative "../../io/buffered_source"

module Dexpace
  # HTTP-41/BODY-14's single-use response body: a handle over the Dexpace::IO::BufferedSource the
  # transport built with .wrapping, so closing this closes the transport stream (IO-6).
  #
  # #source returns THE SAME underlying handle every time and never a fresh replay -- that is
  # BODY-14 literally, and repeatable access is what Dexpace::ResponseLoggingBody and
  # Dexpace::Body.buffer_bounded exist for.
  #
  # The include order is Dexpace::Body THEN Dexpace::Closeable, so Closeable#close sits nearer the
  # class than the module's no-op default and wins (P3-23).
  class ResponseBody
    include Dexpace::Body
    include Dexpace::Closeable

    attr_reader :source, :media_type, :content_length

    # `resource-management/bf5560dc`'s block form, and this is phase 3b's only closable factory:
    # with a block the body is closed on ANY exit path and the block's value is returned; without
    # one the caller owns the close. The bare `super` forwards the block to #initialize
    # implicitly, which is inert: #initialize never yields. (An explicit `&nil` would say so
    # louder, and strict Steep refuses a nil block-pass.)
    def self.new(source:, media_type: nil, content_length: -1)
      body = super
      return body unless block_given?

      begin
        yield body
      ensure
        body.close
      end
    end

    # The source is checked as a duck, never with is_a?, and the duck is the BufferedSource
    # vocabulary this class actually uses: #read_into for #write_to's exact copy, and #peek for
    # #preview -- the narrowest member only a Dexpace::IO::BufferedSource (or a view of one)
    # answers, and the one Response#body_string's #read_string and #body_bytes' #read sit beside.
    # A bare Dexpace::IO::_Source is deliberately NOT enough (review round 0, R0-5): it would
    # construct and then fail with a NoMethodError on the first preview or read through Response,
    # and the contract this class states -- #source -> Dexpace::IO::BufferedSource -- is what the
    # sig declares.
    def initialize(source:, media_type: nil, content_length: -1)
      unless source.respond_to?(:read_into) && source.respond_to?(:peek)
        raise Dexpace::InvalidArgumentError,
              "a response body's source must be a Dexpace::IO::BufferedSource-shaped reader " \
              "responding to #read_into and #peek, got #{source.class}"
      end
      unless content_length.is_a?(::Integer) && content_length >= -1
        raise Dexpace::InvalidArgumentError,
              "content_length must be an Integer of -1 or more, got #{content_length.inspect}"
      end

      @source = source
      @media_type = media_type
      @content_length = content_length
      initialize_closeable(owned: true)
      initialize_single_use
    end

    # BODY-33's non-consuming preview, and BODY-32's cap rules on top of it: a negative cap is
    # rejected, the cap is SILENTLY clamped down to Dexpace::IO::MAX_MATERIALIZED_BYTES and never
    # up, and whatever bytes are available up to the clamped cap come back without requiring that
    # exactly that many exist. Reads through a FRESH #peek view closed in an ensure, so the primary
    # read path does not move; empty when the source is exhausted. ("Null when there is no body" is
    # the caller's nil check on response.body, which is phase 4's call site.)
    #
    # The ceiling is read from the constant and takes NO keyword: a `ceiling:` keyword would let one
    # stream carry two ceilings, which is exactly what design §10.18's single substituted constant
    # exists to prevent. What BODY-32 parameterises is the CAP, which is a different thing.
    def preview(cap:)
      limit = Dexpace::Body.send(:clamp_cap, cap)
      view = @source.peek
      begin
        view.read(limit) || (+"").b
      ensure
        view.close
      end
    end

    # BODY-14: a response body is a reader. It writes once, and a second write raises rather than
    # silently emitting nothing -- offering an already-read response body as a request body without
    # materialising it is the failure BODY-14 describes.
    def write_to(sink)
      claim_single_use!
      return copy_exactly(@source, sink, @content_length) unless @content_length.negative?

      written = 0
      @source.each { |chunk| written += emit_exactly(sink, chunk) }
      written
    end

    # HTTP-46 is Dexpace::Body's identity default: two different live sources are two different
    # values.

    private

    # BODY-15: releases the underlying transport resource, idempotent through Closeable's latch,
    # and makes no assumption that the body was read -- a caller that skips the body entirely still
    # relies on this to release the connection.
    def release
      @source.close if @source.respond_to?(:close)
      nil
    end
  end
end
