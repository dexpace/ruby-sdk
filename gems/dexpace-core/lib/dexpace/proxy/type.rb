# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Proxy
    # The proxy protocol (CFG-22): HTTP, SOCKS4 or SOCKS5, as a frozen Data over a frozen table
    # with .of as its only lookup -- never a Symbol and never an enum library
    # (type-system/545949a5). The set is closed BY the requirement, so it is closed structurally
    # in phase 4c's Stage shape (P4-32, P4-56) rather than phase 1's Status shape: both generated
    # constructors are private, there is no .build, and #with refuses, because Data#with would
    # otherwise mint a fourth member .of cannot find. A dup or a Marshal round-trip is == its
    # constant and not equal? to it; .of canonicalises either back to the constant.
    #
    # Reopens `class Proxy`, which proxy.rb declares and requires this file from; it never
    # appears in lib/dexpace.rb.
    class Type < Data.define(:name)
      include Model

      private_class_method :new, :[]

      NAMES = %w[HTTP SOCKS4 SOCKS5].freeze
      private_constant :NAMES

      # @param name [String] one of the three names, exactly
      def initialize(name:)
        text = Model.required!("proxy type", name)
        unless NAMES.include?(text)
          raise InvalidArgumentError,
                "unknown proxy type #{name.inspect}; one of HTTP, SOCKS4, SOCKS5"
        end

        super(name: Model.frozen_string(text))
      end

      # An HTTP proxy; what a system-property host and an http:// or https:// URL resolve to.
      HTTP = new(name: "HTTP")
      # A SOCKS4 proxy; what a socks4:// URL resolves to.
      SOCKS4 = new(name: "SOCKS4")
      # A SOCKS5 proxy; what a socks5:// URL resolves to.
      SOCKS5 = new(name: "SOCKS5")

      # Not public: P5-1 fixes Type's surface at three constants, and an exposed table is a fourth
      # NFR-4-locked name with one caller.
      ALL = [HTTP, SOCKS4, SOCKS5].freeze
      private_constant :ALL

      # The one lookup: a token in any case, trimmed, a Symbol, or a Type (which resolves to its
      # constant, so a copy is canonicalised).
      #
      # @param token [String, Symbol, Type]
      # @return [Type] the shared instance
      # @raise [Dexpace::InvalidArgumentError] on an unknown, blank or absent token
      def self.of(token)
        text = Model.required!("proxy type", token)
        text = text.name if text.is_a?(Type)
        # upcase with no argument (Dexpace/NoLocaleCaseFold): "socks5".upcase(:turkic) is fine
        # today and the rule exists so nobody has to know that.
        wanted = text.to_s.strip.upcase
        ALL.find { |type| type.name == wanted } ||
          raise(InvalidArgumentError,
                "unknown proxy type #{token.inspect}; one of HTTP, SOCKS4, SOCKS5",)
      end

      # The closed set has no derivation (P4-56): there is no Type.build for Model#with to route
      # through, and Data#with would mint a member .of cannot find.
      #
      # @raise [Dexpace::InvalidArgumentError] always
      def with(_changes = nil)
        raise InvalidArgumentError,
              "the proxy type set is closed at HTTP, SOCKS4 and SOCKS5 and a Type cannot be " \
              "derived; use the constants on Dexpace::Proxy::Type"
      end
    end
  end
end
