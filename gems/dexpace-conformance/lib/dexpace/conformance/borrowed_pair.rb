# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace/model"
require "dexpace/error/invalid_argument_error"

module Dexpace
  module Conformance
    # What a driver's `borrow:` factory returns (suite contract 4a): the transport wrapping the
    # caller's own native client, and a probe answering "is that client still usable?". The probe
    # is the adapter's, because only the adapter knows what using its native client looks like --
    # a Net::HTTP round trip on one, an Async::HTTP::Client one on the other -- and that is what
    # keeps TRANSPORT-15's borrowed half portable across adapters that share no client class, and
    # what keeps a native client class out of this gem's lib/ altogether.
    class BorrowedPair < Data.define(:transport, :probe)
      include Model

      private_class_method :new

      # The validating factory every construction path goes through.
      #
      # @param transport [Object] the borrowing transport, wrapping the caller's own client
      # @param probe [#call] answers truthy while the caller's client still works
      # @return [BorrowedPair] frozen
      # @raise [Dexpace::InvalidArgumentError] naming the member
      def self.build(transport:, probe:)
        new(transport: transport, probe: probe)
      end

      def initialize(transport:, probe:)
        Model.required!("transport", transport)
        raise InvalidArgumentError, "probe must respond to #call" unless
          Model.required!("probe", probe).respond_to?(:call)

        super
      end

      # Whether the caller's own client still works, per the adapter's probe -- asked after the
      # borrowing transport was closed, which is TRANSPORT-15's whole borrowed clause.
      #
      # @return [Boolean]
      def still_usable?
        probe.call ? true : false
      end
    end
  end
end
