# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "failure"

module Dexpace
  module Conformance
    # XCUT-11's structural half, as one predicate (design R8, P9-9).
    #
    # **The rule is a disjunction, and both halves matter.** A frozen instance conforms on
    # `frozen?` alone: it cannot hold per-call state, whatever its ivars say. An UNFROZEN one
    # conforms only when every instance variable it holds is one the DRIVER declared -- a
    # `Thread::Mutex` with the state it guards, or Closeable's `@closed` latch.
    #
    # Two ways to get it wrong, both measured against the real tree. A *frozen and no ivars* rule
    # condemns three conforming first-party subjects outright -- `Instrumentation::Redactor::DEFAULT`
    # (frozen, `[:@policy]`), `Instrumentation::Logger::NULL` (frozen, six ivars) and
    # `ContextStore.default` (unfrozen, `[:@map]`, a BoundedMap with its own mutex) -- and would
    # condemn the exact latch shape `cross-cutting-invariants/89eb6533` prescribes. And reading
    # `mutable:` OFF the audited object inverts the requirement the other way: a conforming
    # latch-plus-mutex Closeable fails, because no phase committed to such a method and R6 forbids
    # phase 9 adding one, while the identical per-call-state bug passes by declaring its own ivar
    # exempt. So the declaration is the driver's, and the audited object gets no vote on its own
    # exemption.
    module SharedInstance
      extend self

      # @param object [Object] the shared instance under audit
      # @param mutable [Array<Symbol>] ivars the DRIVER declares as guarded state or a close latch
      # @param ids [Array<String>] requirement IDs the raised Failure carries
      # @return [nil]
      # @raise [Failure] when an unfrozen shared instance holds an undeclared instance variable
      def audit(object, mutable: [], ids: ["XCUT-11"])
        return nil if object.frozen?

        undeclared = object.instance_variables - mutable
        return nil if undeclared.empty?

        raise Failure.new(
          "#{object.class} is shared across concurrent requests and holds undeclared mutable state",
          expected: mutable.sort, actual: object.instance_variables.sort, requirement_ids: ids,
        )
      end
    end
  end
end
