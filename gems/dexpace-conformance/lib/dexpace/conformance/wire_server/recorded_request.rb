# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace/model"

module Dexpace
  module Conformance
    class WireServer
      # One request as it reached the wire: the head (the request line and the header lines, raw,
      # BINARY, each still ending in CRLF) and the body the server read under its Content-Length
      # or chunked framing (BINARY, empty when there was none). A phase-1-shaped value: `.new`
      # private, a validating `.build`, frozen, its collections owned.
      class RecordedRequest < Data.define(:head, :body)
        include Model

        private_class_method :new

        # @param head [Array<String>] the raw head lines
        # @param body [String] the body bytes
        # @return [RecordedRequest] frozen
        def self.build(head:, body:)
          new(head: head, body: body)
        end

        def initialize(head:, body:)
          super(head: Model.own(Model.required!("head", head).map(&:b)),
                body: Model.required!("body", body).b.freeze,)
        end

        # The request line without its CRLF, e.g. `GET /pets/7 HTTP/1.1`.
        #
        # @return [String]
        def request_line
          head.first.to_s.chomp
        end

        # The request target, the second word of the request line.
        #
        # @return [String]
        def path
          request_line.split[1].to_s
        end

        # The first value of a header, looked up by a fold of the name (the bare `downcase`, never
        # a locale one), or nil. Net::HTTP re-cases every name on the wire (8a's verified fact 11),
        # which is why no assertion reads a header by its exact spelling.
        #
        # @param name [String]
        # @return [String, nil]
        def header(name)
          prefix = "#{name.downcase}:"
          line = head.drop(1).find { |candidate| candidate.downcase.start_with?(prefix) }
          return nil if line.nil?

          line.split(":", 2).last.to_s.strip
        end
      end
    end
  end
end
