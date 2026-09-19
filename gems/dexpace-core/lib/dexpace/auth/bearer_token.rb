# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "validation"

module Dexpace
  module Auth
    # AUTH-8, AUTH-9, AUTH-10: a bearer token and its optional expiry. Value equality over the
    # REAL token and expiry is Data's own and is AUTH-8's text -- the override lives only in the
    # three renderings, never in ==, eql? or hash, and the real fields are never touched to
    # achieve it.
    #
    # Three renderings, not two. Ruby interpolation calls #to_s and a debugger #inspect; but
    # `pp` does not call #inspect on a Data -- pp.rb gives Data its own #pretty_print, which
    # walks the members directly (verified on 3.2.11, 3.4.10 and 4.0.6: a Data with #inspect
    # overridden still pretty-prints as `#<data … token="SECRET">`). So #pretty_print is the
    # third override, and it is the one a reader will not think to write.
    class BearerToken < ::Data.define(:token, :expiry)
      include Model

      private_class_method :new

      # The validating factory; #with routes through it.
      #
      # @param token [String] non-blank (AUTH-9)
      # @param expiry [Time, nil] nil means the token never locally expires (AUTH-10)
      # @return [BearerToken]
      def self.build(token:, expiry: nil)
        new(token: token, expiry: expiry)
      end

      def initialize(token:, expiry:)
        text = Validation.non_blank!("token", token)
        unless expiry.nil? || expiry.is_a?(::Time)
          raise InvalidArgumentError, "expiry must be a Time or nil"
        end

        super(token: Model.frozen_string(text), expiry: expiry)
      end

      # AUTH-10: expired at `now` with margin `margin` iff the expiry is set and (now + margin)
      # is strictly after it. A non-expiring token is never expired, whatever the margin.
      #
      # @param now [Time] the reference instant, a Clock#now reading
      # @param margin [Numeric] seconds of grace, added to `now`
      # @return [Boolean]
      def expired?(now:, margin: 0)
        limit = expiry
        return false if limit.nil?

        (now + margin) > limit
      end

      # @return [String] the token redacted, the expiry visible
      def to_s = "BearerToken(token=#{REDACTED}, expiry=#{expiry.inspect})"

      # @return [String] the token redacted, the expiry visible
      def inspect = "#<Dexpace::Auth::BearerToken token=#{REDACTED} expiry=#{expiry.inspect}>"

      # The rendering `pp` uses; see the class comment.
      #
      # @param printer [PP]
      # @return [void]
      def pretty_print(printer)
        printer.text(inspect)
      end
    end
  end
end
