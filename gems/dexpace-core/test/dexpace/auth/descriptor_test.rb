# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require_relative "../../../lib/dexpace/auth/descriptor"

# Exercises: AUTH-3 -- a non-empty ordered requirement list, refused empty at construction,
# immutable in and out, and allows_anonymous? true iff a requirement's scheme is NO_AUTH.
class DexpaceAuthDescriptorTest < DexpaceTestCase
  Descriptor = Dexpace::Auth::Descriptor
  Requirement = Dexpace::Auth::Requirement
  Scheme = Dexpace::Auth::Scheme

  def requirement(scheme) = Requirement.build(scheme: scheme)

  test "AUTH-3: an ordered list in caller preference order" do
    descriptor = Descriptor.build(requirements: [requirement(:digest), requirement(:basic)])

    assert_equal([Scheme::DIGEST, Scheme::BASIC], descriptor.requirements.map(&:scheme))
  end

  test "AUTH-3: an empty list is refused at construction with the SDK's argument error" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Descriptor.build(requirements: []) }

    assert_includes(error.message, "non-empty")
    assert_raises(Dexpace::InvalidArgumentError) { Descriptor.build(requirements: nil) }
    assert_raises(Dexpace::InvalidArgumentError) { Descriptor.build(requirements: ["basic"]) }
  end

  test "AUTH-3: defensive copy in, read-only view out" do
    list = [requirement(:basic)]
    descriptor = Descriptor.build(requirements: list)
    list << requirement(:digest)

    assert_equal(1, descriptor.requirements.size)
    assert_predicate(descriptor.requirements, :frozen?)
    assert_same(descriptor.requirements, descriptor.requirements)
    assert_raises(FrozenError) { descriptor.requirements << requirement(:digest) }
  end

  test "AUTH-3: allows_anonymous? is true iff any requirement's scheme is NO_AUTH" do
    assert_predicate(Descriptor.build(requirements: [requirement(:no_auth)]), :allows_anonymous?)
    assert_predicate(Descriptor.build(requirements: [requirement(:basic), requirement(:no_auth)]),
                     :allows_anonymous?,)
    refute_predicate(Descriptor.build(requirements: [requirement(:basic), requirement(:oauth2)]),
                     :allows_anonymous?,)
  end

  test "the construction pattern: .new private, value equality, #with through .build" do
    refute_respond_to(Descriptor, :new)
    a = Descriptor.build(requirements: [requirement(:basic)])
    b = Descriptor.build(requirements: [requirement(:basic)])

    assert_equal(a, b)
    assert_equal([Scheme::DIGEST],
                 a.with(requirements: [requirement(:digest)]).requirements.map(&:scheme),)
    assert_raises(Dexpace::InvalidArgumentError) { a.with(requirements: []) }
  end
end
