# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Transport
    module AsyncHTTP
      # A `Protocol::HTTP::Body::Readable` over a Dexpace::Body, so an outbound body is never
      # materialised: the library pulls one `#read` per chunk plus one for end of stream and
      # frames a body of unknown length as chunked (the design's verified fact 7).
      # `Protocol::HTTP::Body::Buffered.wrap` is deliberately NOT used -- it materialises an
      # `#each`-yielding object in full, which is SEAM-11's streaming intent broken on the write
      # side.
      #
      # The pull is phase 3a's own `Dexpace::IO::BufferedSource.over(body)`, which owns nothing
      # and reads `#each` on demand; a replayable body is re-read through a fresh source on
      # `#rewind`, and a single-use one refuses -- the second of TRANSPORT-17's two independent
      # guarantees on this adapter beside `retries: 0`. A private_constant of AsyncHTTP.
      class RequestBody < ::Protocol::HTTP::Body::Readable
        # One pull's ceiling; a chunk the body yields is never split below it and never coalesced
        # beyond it.
        READ_SIZE = 65_536
        private_constant :READ_SIZE

        # @param body [Dexpace::Body]
        def initialize(body)
          super()
          @body = body
          @source = ::Dexpace::IO::BufferedSource.over(body)
        end

        # The library's own protocol: an Integer frames the body with Content-Length, nil frames
        # it chunked. BODY-35's -1 sentinel is this adapter's nil.
        #
        # @return [Integer, nil]
        def length
          value = @body.content_length
          value.negative? ? nil : value
        end

        # @return [Boolean] whether `#rewind` will succeed -- the body's own BODY-1 answer
        def rewindable?
          @body.replayable?
        end

        # A fresh source over a replayable body; false for a single-use one, so the library's own
        # `Request#retry!` never re-reads it even at a non-zero retry count.
        #
        # @return [Boolean]
        def rewind # rubocop:disable Naming/PredicateMethod -- the library's own name for a command reporting whether it took effect, as Async::Pool's own bodies spell it
          return false unless rewindable?

          @source = ::Dexpace::IO::BufferedSource.over(@body)
          true
        end

        # One chunk, BINARY, or nil at end of stream.
        #
        # @return [String, nil]
        def read
          @source.readpartial(READ_SIZE).b
        rescue ::Dexpace::EndOfStreamError
          nil
        end

        # Releases the pull source; the Dexpace::Body itself is the caller's and is never closed
        # here (design §10.12: a body closes exactly the sources it opened, and this opened none).
        #
        # @param error [Exception, nil] the library's own argument, unused
        # @return [nil]
        def close(error = nil)
          super
          @source.close
          nil
        end
      end

      private_constant :RequestBody
    end
  end
end
