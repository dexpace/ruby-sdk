# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  module Auth
    # AUTH-1: the closed set the descriptor/resolver layer recognizes -- exactly OAUTH2, API_KEY,
    # BASIC, DIGEST and NO_AUTH -- as a frozen Data over a frozen table with .of as its only
    # lookup, never a Symbol and never an enum library (type-system/545949a5). The set is closed
    # BY the requirement, so it is closed structurally in phase 4c's Stage shape (P4-32, P4-56):
    # both generated constructors are private, there is no .build, and #with refuses, because
    # Data#with would otherwise mint a sixth member .of cannot find. The five constants are
    # built through the private .new exactly as phase 1's Method builds its own -- never
    # `allocate` plus `instance_variable_set`, which leaves every member nil on a Data (verified
    # on 3.2.11, 3.4.10 and 4.0.6: a Data's members are not instance variables).
    #
    # NO_AUTH is a sentinel meaning "this operation may run anonymously", never a wire scheme:
    # the resolver treats it as always satisfiable (AUTH-5) and the step's stamper for it is
    # Step::NO_STAMP.
    class Scheme < ::Data.define(:name)
      include Model

      private_class_method :new, :[]

      NAMES = %w[OAUTH2 API_KEY BASIC DIGEST NO_AUTH].freeze
      private_constant :NAMES

      # @param name [String] one of the five names, exactly
      def initialize(name:)
        text = Model.required!("scheme", name)
        unless NAMES.include?(text)
          raise InvalidArgumentError,
                "unknown auth scheme #{name.inspect}; one of #{NAMES.join(", ")} (AUTH-1)"
        end

        super(name: Model.frozen_string(text))
      end

      # OAuth 2.0 / OpenID Connect bearer credentials.
      OAUTH2 = new(name: "OAUTH2")
      # A static API key carried in a header (AUTH-26).
      API_KEY = new(name: "API_KEY")
      # RFC 7617 Basic.
      BASIC = new(name: "BASIC")
      # RFC 7616 Digest.
      DIGEST = new(name: "DIGEST")
      # The anonymous sentinel: no credential is stamped.
      NO_AUTH = new(name: "NO_AUTH")

      # The whole population, in AUTH-1's order. Public, unlike Proxy::Type's table, because the
      # requirement is stated as a set and a caller building an `available_schemes` list has to
      # be able to say "every scheme I can supply" without spelling five constants.
      ALL = [OAUTH2, API_KEY, BASIC, DIGEST, NO_AUTH].freeze

      # The one lookup: a token in any case, trimmed, a Symbol, or a Scheme (which resolves to
      # its constant, so a dup or a Marshal copy is canonicalised).
      #
      # @param token [String, Symbol, Scheme]
      # @return [Scheme] the shared instance
      # @raise [Dexpace::InvalidArgumentError] on an unknown, blank or absent token
      def self.of(token)
        text = Model.required!("scheme", token)
        text = text.name if text.is_a?(Scheme)
        # upcase with no argument (Dexpace/NoLocaleCaseFold): the fold is locale-independent.
        wanted = text.to_s.strip.upcase
        ALL.find { |scheme| scheme.name == wanted } ||
          raise(InvalidArgumentError,
                "unknown auth scheme #{token.inspect}; one of #{NAMES.join(", ")} (AUTH-1)",)
      end

      # The closed set has no derivation (P4-56): there is no Scheme.build for Model#with to
      # route through, and Data#with would mint a member .of cannot find.
      #
      # @raise [Dexpace::InvalidArgumentError] always
      def with(_changes = nil)
        raise InvalidArgumentError,
              "the auth scheme set is closed at #{NAMES.join(", ")} and a Scheme cannot be " \
              "derived; use the constants on Dexpace::Auth::Scheme"
      end

      # The name, so a scheme interpolates as `OAUTH2` rather than as a Data dump.
      def to_s = name
    end
  end
end
