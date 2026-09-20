# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../serde"
require_relative "../error/invalid_argument_error"

module Dexpace
  # Reopened for the witness protocol, the way closeable.rb defines Dexpace.close_quietly on the
  # root namespace: the seam module is phase 2's serde.rb and this file adds the four names the
  # protocol needs, in the file that mirrors them (design §7.3, §10.14).
  module Serde
    # The one name a witness answers: `.dexpace_load(parsed, ctx)`, a class method on a model
    # class or an instance method on a combinator. Public, and frozen as every Symbol is, so a code
    # generator emitting witnesses reads the name from here rather than hard-coding a string this
    # repository could rename; `Native`'s walk and `.witness?` both read it, so `:dexpace_load` is
    # written exactly once.
    WITNESS_METHOD = :dexpace_load

    # The one name an encodable value answers: `#dexpace_dump`, a zero-argument instance method
    # returning the value's codec-native form (a Hash, an Array, a scalar, or OMIT). The encode side
    # takes no context, because Ruby erases nothing -- every object carries its class -- so there
    # is no DumpContext and this is the whole protocol.
    DUMP_METHOD = :dexpace_dump

    class << self
      # Whether `object` is a witness: anything responding to .dexpace_load(parsed, ctx). A
      # `respond_to?` test and never a nominal one, for the reason every seam here gives -- a model
      # class implements the protocol as a class method and a combinator instance as an instance
      # method, and one predicate must cover both (verified fact 15). The set of witnesses is
      # therefore OPEN: a caller writes a Set witness or a discriminated-union witness with no
      # registration, no subclassing and no core change, in two lines:
      #
      #   class SetOf
      #     def initialize(element) = @element = Dexpace::Serde.witness!(element)
      #     def dexpace_load(parsed, ctx) = ctx.array!(parsed).each_with_index.to_set { |v, i| ... }
      #   end
      #
      # A `#call`-shaped object is deliberately NOT a witness. SERDE-5 requires an explicit runtime
      # type witness and SERDE-8 requires construction to fail fast without one; a `#call` fallback
      # would make every lambda a witness and both MUSTs unenforceable.
      #
      # @param object [Object]
      # @return [Boolean]
      def witness?(object) = object.respond_to?(WITNESS_METHOD)

      # SERDE-8's raising half: the object back when it is a witness, and an actionable
      # InvalidArgumentError naming the missing method and the object's class otherwise. Every
      # combinator's `.of` and both response handlers' `.build` run their arguments through this,
      # which is what puts the failure at witness CONSTRUCTION -- earlier than the reference's
      # binder-resolution failure -- and what makes SERDE-8's "unresolved type variable" state
      # unreachable: a combinator cannot exist without a concrete element witness.
      #
      # @param object [Object]
      # @return [Object] `object`
      # @raise [Dexpace::InvalidArgumentError] when `object` does not answer .dexpace_load
      def witness!(object)
        return object if witness?(object)

        raise InvalidArgumentError,
              "a witness must respond to .#{WITNESS_METHOD}(parsed, ctx); #{object.class} does not"
      end
    end
  end
end
