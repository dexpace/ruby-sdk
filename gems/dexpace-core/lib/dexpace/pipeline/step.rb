# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../registry"

module Dexpace
  class Pipeline
    # The step protocol (PIPE-11, PIPE-12), mirroring Dexpace::Transport's shape one arity lower:
    # a step is any object responding to #call(request, cursor). It receives the inbound request,
    # MAY call cursor.call to invoke the rest of the chain -- with a substituted request, which
    # then sticks (PIPE-14) -- MAY inspect or substitute the outbound response before returning
    # it, and MAY short-circuit by returning a synthetic response without calling the cursor at
    # all (PIPE-12).
    #
    # A step is a duck type: `include Dexpace::Pipeline::Step` is neither required nor
    # meaningful, because design §5.1's requirement is that a lambda qualifies as a step and a
    # module a lambda cannot include cannot be the gate. The module exists so NFR-11's RBS scan has
    # a named home for the protocol -- the interfaces _Step and _AsyncStep in sig/ -- and so the
    # predicate lives once.
    #
    # A single step is shared across every call (PIPE-11), so it holds no per-call state: whatever
    # a step needs to remember for one send lives on the cursor it was handed, is passed as an
    # argument, and is never read from ambient storage -- not Fiber[], not Thread.current[]. A
    # step that spawns a thread or a fiber hands it the cursor explicitly; nothing is inherited.
    #
    # No registry. Dexpace::Registry has three seam instances and this phase adds no fourth: a
    # step is something a caller builds and installs, not something the SDK discovers.
    module Step
      # Phase 2's predicate, one arity lower, reused rather than reimplemented -- "required <= 2
      # and (a rest parameter is present or required + optional >= 2)", with the :opt handling
      # that lets a non-lambda `proc { |request, cursor| }` through, and phase 2's NameError
      # fallback for an object whose #parameters cannot be read (verified fact 1).
      #
      # It cannot tell a sync step from an async one, because they differ only in return type --
      # phase 2's admitted gap arriving at a second seam, and why Builder has #build and
      # #build_async rather than one method with a flag (P4-30).
      #
      # @param object [Object] anything
      # @return [Boolean] whether it is callable with two positional arguments
      def self.conforms?(object) = Dexpace::Registry.callable?(object, arity: 2)
    end
  end
end
