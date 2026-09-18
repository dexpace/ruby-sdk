# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../auth"
require_relative "../error/invalid_argument_error"
require_relative "../error/auth_resolution_error"
require_relative "scheme"
require_relative "descriptor"

module Dexpace
  module Auth
    # AUTH-4–AUTH-7: tier resolution as a pure function. A module with `extend self` and no
    # instance -- the shape §6.1 gives the resilience policy and 5a gave Dexpace::Retryability --
    # because AUTH-7 requires the resolver to be "stateless and safe for concurrent use" with "a
    # single shared instance" as "a valid entry point": a module IS the single shared entry point,
    # with nothing to instantiate and nothing to race on.
    module Resolver
      extend self

      # Tier selection is strict (AUTH-4): the first PRESENT tier is the only one consulted, and
      # a present tier that cannot be satisfied fails rather than falling through -- which the
      # `||` chain gets right by construction, since once `per_call` is non-nil it is used
      # exclusively whether or not its search finds anything. Within the selected descriptor the
      # first requirement in declared order whose scheme is NO_AUTH or is in `available_schemes`
      # wins (AUTH-5). No concrete credential is ever received, so none can be inspected.
      #
      # @param per_call [Descriptor, nil] the per-call override
      # @param operation [Descriptor, nil] the operation's descriptor
      # @param client [Descriptor, nil] the client's descriptor
      # @param available_schemes [Enumerable<Scheme, String, Symbol>] the schemes the caller can
      #   supply a credential for; each is resolved through Scheme.of
      # @return [Requirement] the selected requirement
      # @raise [Dexpace::InvalidArgumentError] when all three tiers are absent (AUTH-6)
      # @raise [Dexpace::AuthResolutionError] when the selected descriptor lists no satisfiable
      #   scheme (AUTH-6)
      def resolve(per_call:, operation:, client:, available_schemes:)
        descriptor = selected!(per_call || operation || client)
        available = available_schemes.map { |scheme| Scheme.of(scheme) }
        requirement = first_satisfiable(descriptor, available)
        return requirement unless requirement.nil?

        raise AuthResolutionError.new(required: descriptor.requirements.map(&:scheme),
                                      available: available,)
      end

      private

      # AUTH-5: declared order, NO_AUTH always satisfiable, membership otherwise.
      def first_satisfiable(descriptor, available)
        descriptor.requirements.find do |candidate|
          candidate.scheme == Scheme::NO_AUTH || available.include?(candidate.scheme)
        end
      end

      # AUTH-6's first failure, and the type of the tier that was selected.
      def selected!(descriptor)
        if descriptor.nil?
          raise InvalidArgumentError,
                "an auth descriptor is required at the per-call, operation or client tier (AUTH-6)"
        end
        return descriptor if descriptor.is_a?(Descriptor)

        raise InvalidArgumentError, "a tier must hold a Dexpace::Auth::Descriptor"
      end
    end
  end
end
