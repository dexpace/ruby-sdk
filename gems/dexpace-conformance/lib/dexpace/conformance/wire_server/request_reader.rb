# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "recorded_request"

module Dexpace
  module Conformance
    class WireServer
      # Reads one HTTP/1.1 request off an accepted socket: the head line by line up to the blank
      # line, then the body under the framing the head declares -- the exact count under
      # Content-Length, the de-chunked bytes under Transfer-Encoding: chunked, nothing otherwise --
      # so an upload is observable byte for byte. A private_constant of WireServer.
      module RequestReader
        extend self

        # @param conn [Object] the accepted socket
        # @return [RecordedRequest, nil] nil when the peer sent nothing
        def read(conn)
          head = [] #: Array[String]
          while (line = conn.gets)
            head << line
            break if line == "\r\n"
          end
          return nil if head.empty?

          RecordedRequest.build(head: head, body: read_body(conn, head))
        end

        private

        def read_body(conn, head)
          length = header_value(head, "content-length")
          return read_exactly(conn, length.to_i) if length&.match?(/\A[0-9]+\z/)

          encoding = header_value(head, "transfer-encoding")
          return read_chunked(conn) if encoding&.downcase&.include?("chunked")

          (+"").b
        end

        def header_value(head, folded)
          line = head.find { |candidate| candidate.downcase.start_with?("#{folded}:") }
          return nil if line.nil?

          line.split(":", 2).last.to_s.strip
        end

        def read_exactly(conn, count)
          return (+"").b if count.zero?

          (conn.read(count) || "").b
        end

        def read_chunked(conn)
          body = (+"").b
          loop do
            size_line = conn.gets
            break if size_line.nil?

            size = size_line.strip.split(";").first.to_i(16)
            break if size.zero?

            body << (conn.read(size) || "").b
            conn.read(2) # the chunk's CRLF
          end
          # The trailer section, up to and including the blank line.
          while (line = conn.gets)
            break if line == "\r\n"
          end
          body
        end
      end
      private_constant :RequestReader
    end
  end
end
