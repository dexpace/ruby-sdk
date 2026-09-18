# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/resolver"

# Exercises: AUTH-4, AUTH-5, AUTH-6, AUTH-7 -- strict tier selection with no fall-through,
# first-satisfiable-in-declared-order within the tier, NO_AUTH always satisfiable, the two
# distinct failures, and a stateless module usable from many threads at once.
class DexpaceAuthResolverTest < DexpaceTestCase
  Resolver = Dexpace::Auth::Resolver
  Descriptor = Dexpace::Auth::Descriptor
  Requirement = Dexpace::Auth::Requirement
  Scheme = Dexpace::Auth::Scheme

  def descriptor(*schemes)
    Descriptor.build(requirements: schemes.map { |scheme| Requirement.build(scheme: scheme) })
  end

  def resolve(per_call: nil, operation: nil, client: nil, available: [])
    Resolver.resolve(per_call: per_call, operation: operation, client: client,
                     available_schemes: available,)
  end

  test "AUTH-4: the most specific present tier is selected, per-call over operation over client" do
    all_three = resolve(per_call: descriptor(:digest), operation: descriptor(:basic),
                        client: descriptor(:oauth2), available: Scheme::ALL,)

    assert_same(Scheme::DIGEST, all_three.scheme)
    assert_same(Scheme::BASIC, resolve(operation: descriptor(:basic), client: descriptor(:oauth2),
                                       available: Scheme::ALL,).scheme,)
    assert_same(Scheme::OAUTH2, resolve(client: descriptor(:oauth2), available: Scheme::ALL).scheme)
  end

  test "AUTH-4: a present higher tier that cannot be satisfied fails and never falls through" do
    error = assert_raises(Dexpace::AuthResolutionError) do
      resolve(per_call: descriptor(:digest), client: descriptor(:basic), available: [:basic])
    end

    assert_equal([Scheme::DIGEST], error.required)
    assert_equal([Scheme::BASIC], error.available)
  end

  test "AUTH-5: the first requirement in declared order whose scheme is satisfiable wins" do
    descriptor = descriptor(:digest, :basic, :oauth2)

    assert_same(Scheme::BASIC, resolve(per_call: descriptor, available: %i[oauth2 basic]).scheme)
    assert_same(Scheme::DIGEST, resolve(per_call: descriptor, available: Scheme::ALL).scheme)
  end

  test "AUTH-5: NO_AUTH is always satisfiable, with nothing available at all" do
    assert_same(Scheme::NO_AUTH,
                resolve(client: descriptor(:basic, :no_auth), available: []).scheme,)
  end

  test "AUTH-5: satisfiability is membership of the available set; no credential is inspected" do
    assert_same(Scheme::BASIC, resolve(client: descriptor(:basic), available: ["basic"]).scheme)
    copy = Scheme::BASIC.dup

    assert_same(Scheme::BASIC, resolve(client: descriptor(:basic), available: [copy]).scheme)
  end

  test "AUTH-6: every tier absent is the argument error, not the resolution error" do
    error = assert_raises(Dexpace::InvalidArgumentError) { resolve }

    assert_includes(error.message, "AUTH-6")
    refute_kind_of(Dexpace::AuthResolutionError, error)
  end

  test "AUTH-6: no satisfiable scheme is the resolution error carrying both lists in order" do
    error = assert_raises(Dexpace::AuthResolutionError) do
      resolve(operation: descriptor(:digest, :oauth2), available: %i[basic api_key])
    end

    assert_equal([Scheme::DIGEST, Scheme::OAUTH2], error.required)
    assert_equal([Scheme::BASIC, Scheme::API_KEY], error.available)
    assert_kind_of(Dexpace::Error, error)
    assert_includes(error.message, "DIGEST, OAUTH2")
  end

  test "a tier that is not a Descriptor is refused" do
    assert_raises(Dexpace::InvalidArgumentError) { resolve(client: "basic") }
  end

  test "AUTH-7: a module with no state, deterministic, and safe from twenty threads at once" do
    descriptor = descriptor(:digest, :no_auth)
    results = Array.new(20)
    threads = Array.new(20) do |index|
      Thread.new { results[index] = resolve(client: descriptor, available: []).scheme }
    end
    threads.each(&:join)

    assert_equal([Scheme::NO_AUTH] * 20, results)
    assert_empty(Resolver.instance_variables)
  end
end
