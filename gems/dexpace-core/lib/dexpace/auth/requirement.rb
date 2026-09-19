# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"
require_relative "scheme"

module Dexpace
  module Auth
    # AUTH-2: one scheme bound to its own OAuth scopes and params. The two collections are
    # meaningful only for OAUTH2 -- resolution never inspects them for any scheme (AUTH-5) --
    # and are retained for every scheme, because the requirement says "still preserved for
    # caller inspection". Value equality over all three members is Data's own and is AUTH-2's
    # text.
    #
    # Ownership is taken through Model.own, phase 1's deep copy-and-freeze, and NOT through
    # `dup.freeze`: dup is shallow, and AUTH-2's "retained input collections mutated by the
    # caller after construction MUST NOT affect the stored value" covers a caller mutating a
    # String INSIDE the array. Verified on 3.2.11, 3.4.10 and 4.0.6: with dup.freeze, a caller's
    # `scopes[0] << ":write"` after construction turns the stored ["read"] into ["read:write"];
    # with Model.own the stored value is untouched.
    class Requirement < ::Data.define(:scheme, :scopes, :params)
      include Model

      private_class_method :new

      # The validating factory every construction path goes through; #with routes here.
      #
      # @param scheme [Scheme, String, Symbol] resolved through Scheme.of, as Request resolves
      #   its method through Method.of
      # @param scopes [Array<String>] OAuth scopes; copied and deep-frozen
      # @param params [Hash] OAuth params; copied and deep-frozen
      # @return [Requirement]
      def self.build(scheme:, scopes: [], params: {})
        new(scheme: scheme, scopes: scopes, params: params)
      end

      def initialize(scheme:, scopes:, params:)
        resolved = Scheme.of(scheme)
        unless Model.required!("scopes", scopes).is_a?(::Array)
          raise InvalidArgumentError, "scopes must be an Array"
        end
        unless Model.required!("params", params).is_a?(::Hash)
          raise InvalidArgumentError, "params must be a Hash"
        end

        super(scheme: resolved, scopes: Model.own(scopes), params: Model.own(params))
      end
    end
  end
end
