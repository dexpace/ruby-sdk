# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require "dexpace"

# NFR-14, and SEAM-10's replacement. Postponed by phase 0 to phase 2, and built here: the runtime
# half of design §2.3's version-skew guard, which SEAM-10's vacuity (design §10.9) makes the real
# Ruby risk. The comparison is hand-rolled because Gem is undefined under `ruby --disable-gems`
# (verified on 3.2.11 and 4.0.6), so this suite is the only place Gem::Requirement appears -- in a
# test process where Bundler has already loaded it.
class DexpaceRegistryVersionTest < DexpaceTestCase
  def registry
    Dexpace::Registry.new(
      seam: "transport",
      installer: "Dexpace::Transport.install",
      conforms: ->(_object) { true },
    )
  end

  def accepts?(requirement)
    registry.register(:adapter, -> { :provider }, core: requirement)
    true
  rescue Dexpace::SeamError
    false
  end

  # The guard reads Dexpace::VERSION, and while every gem is at 0.0.0 a grid over the requirement
  # alone cannot tell `>=` from `==` on the minor -- `~> 0.0` is the only satisfiable form. So the
  # running version is swapped for the duration of a block, through remove_const so no
  # "already initialized constant" warning is emitted, and restored in the ensure. Test-only.
  def with_running_version(version)
    original = Dexpace::VERSION
    Dexpace.send(:remove_const, :VERSION)
    Dexpace.const_set(:VERSION, version)
    yield
  ensure
    Dexpace.send(:remove_const, :VERSION)
    Dexpace.const_set(:VERSION, original)
  end

  RUNNING = %w[0.0.0 0.1.3 0.2.0 1.0.0 1.2.7 2.3.1].freeze

  test "the hand-rolled comparison agrees with Gem::Requirement over a grid" do
    require "rubygems"

    sample(count: 48, seed: 20_260_907) do |random|
      running = RUNNING.sample(random: random)
      requirement = "~> #{random.rand(0..2)}.#{random.rand(0..3)}"
      expected = Gem::Requirement.new(requirement).satisfied_by?(Gem::Version.new(running))

      with_running_version(running) do
        assert_equal(expected, accepts?(requirement),
                     "#{requirement.inspect} against dexpace-core #{running}",)
      end
    end
  end

  # The grid above is seeded; this is the exhaustive small square, so a comparison right on the
  # samples and wrong on a corner -- `~> 0.0` against 0.1.x is the classic -- cannot slip through.
  test "every two-segment requirement from 0.0 to 2.3 agrees with Gem::Requirement" do
    require "rubygems"

    RUNNING.each do |running|
      with_running_version(running) do
        (0..2).each do |major|
          (0..3).each do |minor|
            requirement = "~> #{major}.#{minor}"
            expected = Gem::Requirement.new(requirement).satisfied_by?(Gem::Version.new(running))

            assert_equal(expected, accepts?(requirement), "#{requirement} against #{running}")
          end
        end
      end
    end
  end

  test "the swapped running version is always restored" do
    with_running_version("9.9.9") { assert_equal("9.9.9", Dexpace::VERSION) }

    assert_match(/\A\d+\.\d+\.\d+\z/, Dexpace::VERSION)
    refute_equal("9.9.9", Dexpace::VERSION)
  end

  test "the current core version satisfies its own major.minor" do
    major, minor, = Dexpace::VERSION.split(".", 3)

    assert(accepts?("~> #{major}.#{minor}"))
  end

  test "a minor ahead of the running core is skew and is loud" do
    major, minor, = Dexpace::VERSION.split(".", 3)

    error = assert_raises(Dexpace::SeamError) do
      registry.register(:adapter, -> { :p }, core: "~> #{major}.#{minor.to_i + 1}")
    end

    assert_match(/was built against dexpace-core/, error.message)
    assert_includes(error.message, Dexpace::VERSION)
    assert_match(/:adapter/, error.message)
  end

  test "a different major is skew in both directions" do
    major, minor, = Dexpace::VERSION.split(".", 3)

    assert_raises(Dexpace::SeamError) do
      registry.register(:adapter, -> { :p }, core: "~> #{major.to_i + 1}.#{minor}")
    end
    assert_raises(Dexpace::SeamError) do
      registry.register(:adapter, -> { :p }, core: "~> #{major.to_i + 2}.#{minor}")
    end
  end

  test "a requirement that is not the two-segment pessimistic form is refused, not reinterpreted" do
    [">= 0.1", "~> 0.1.2", "0.1", "~>0", "", "latest", nil, :"~> 0.0"].each do |requirement|
      error = assert_raises(Dexpace::InvalidArgumentError) do
        registry.register(:adapter, -> { :p }, core: requirement)
      end

      assert_match(/two-segment pessimistic requirement/, error.message, requirement.inspect)
    end
  end

  test "a rejected registration leaves the registry empty" do
    subject = registry

    assert_raises(Dexpace::InvalidArgumentError) do
      subject.register(:adapter, -> { :p }, core: ">= 0.1")
    end

    assert_empty(subject.registered_keys)
  end

  test "core: is required, so a skew check is never silently skipped" do
    assert_raises(::ArgumentError) { registry.register(:adapter, -> { :p }) }
  end
end
