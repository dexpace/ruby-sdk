# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  module Conformance
    # What a CodecSuite assertion receives.
    #
    # The witness and the source factory are the DRIVER's: phase 2's contract is
    # `#load(source, witness)` with no witness-less overload, and the source type is the adapter's
    # (the JSON codec's is a `Dexpace::IO::BufferedSource`), so neither is the suite's to invent.
    class CodecCase
      # A sink that counts its own closes, so SERDE-3's "streaming/buffer targets not closed" is a
      # COUNT and not an inference, and records what was written so an encode can be checked to
      # have produced something at all.
      class CountingSink
        # @return [String] every byte written, in order
        attr_reader :bytes
        # @return [Integer] how many times #close was called
        attr_reader :close_count

        def initialize
          @bytes = +""
          @close_count = 0
        end

        # @param chunk [String] bytes the codec wrote
        # @return [Integer] the running total written
        def write(chunk) = (@bytes << chunk).bytesize
        # @return [Integer] how many closes this sink has now seen -- SERDE-3's count
        def close = @close_count += 1
      end
      private_constant :CountingSink

      # @return [Object] the driver's witness, answering #dexpace_load(parsed, ctx)
      attr_reader :witness

      # @param build [#call] a zero-argument codec factory
      # @param witness [Object] a witness the codec's #load accepts
      # @param source [#call] text -> the source type this codec's #load reads
      def initialize(build:, witness:, source:)
        @build = build
        @witness = witness
        @source = source
      end

      # @return [Object] a fresh codec
      def codec = @build.call

      # @return [CountingSink] a fresh counting sink
      def sink = CountingSink.new

      # @param text [String] the bytes the source yields
      def source(text) = @source.call(text)
    end
  end
end
