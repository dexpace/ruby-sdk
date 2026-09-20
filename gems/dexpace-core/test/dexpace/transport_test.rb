# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/fake_transport"
require_relative "../support/options_ignoring_transport"
require_relative "../support/inline_executor"
require "dexpace"

# SEAM-11, SEAM-12, SEAM-13, SEAM-15, SEAM-2. A transport is any object responding to
# #call(request, options, cancellation) and returning a Dexpace::Response. #call is the convergence
# point of Ruby's own middleware ecosystems (porting-method/bf484e8e, P14), so a bare lambda is a
# valid transport and phase 4's Dexpace::Pipeline can stand in wherever one is expected (PIPE-26).
#
# The properties of a BARE `require "dexpace"` -- an empty registry, the zero-candidate SeamError
# and nothing resolved after a swap -- live in transport_bare_require_test.rb since phase 8a, whose
# adapter registers a factory the moment it is required: in one `rake test:gems` process the
# registry is not empty, and the in-process assertions were the pin that registration invalidated.
class DexpaceTransportTest < DexpaceTestCase
  CORE = "~> 0.0"

  test "conforms? accepts every callable shape that can take the seam's three arguments" do
    assert(Dexpace::Transport.conforms?(->(_request, _options, _cancellation) {}))
    assert(Dexpace::Transport.conforms?(proc { |_request, _options, _cancellation| }))
    assert(Dexpace::Transport.conforms?(->(*) {}))
    assert(Dexpace::Transport.conforms?(FakeTransport.new))
    assert(Dexpace::Transport.conforms?(OptionsIgnoringTransport.new(:response)))
  end

  test "conforms? refuses the wrong arity and anything that is not callable" do
    refute(Dexpace::Transport.conforms?(->(_request) {}))
    refute(Dexpace::Transport.conforms?(->(_request, _options, _cancellation, must:) {}))
    refute(Dexpace::Transport.conforms?(Object.new))
    refute(Dexpace::Transport.conforms?(nil))
  end

  test "install refuses an object that does not implement the seam" do
    error = assert_raises(Dexpace::InvalidArgumentError) { Dexpace::Transport.install(Object.new) }

    assert_match(/must implement the seam/, error.message)
  end

  # The override itself; "and afterwards nothing is resolved" is a property of the bare require
  # and lives in transport_bare_require_test.rb (see the class comment).
  test "swap scopes an override to its block" do
    transport = ->(_request, _options, _cancellation) { :response }
    keys_before = Dexpace::Transport.registered_keys
    resolved = nil

    Dexpace::Transport.swap(transport) { resolved = Dexpace::Transport.resolve }

    assert_same(transport, resolved)
    assert_equal(keys_before, Dexpace::Transport.registered_keys, "the swap registered nothing")
  end

  # An install inside a swap block is part of the override and is restored with it, which is
  # what lets a process-global registry be exercised without leaking into the next test.
  test "install goes through the module, returns it, and is scoped by an enclosing swap" do
    installed = ->(_request, _options, _cancellation) { :installed }

    Dexpace::Transport.swap(:override) do
      assert_same(Dexpace::Transport, Dexpace::Transport.install(installed))
      assert_same(installed, Dexpace::Transport.resolve)
    end
  end

  # The module-level registry is process-global, so the registration is scoped inside a swap and
  # its registration is the one thing swap deliberately keeps -- which is why the key is removed
  # through the private registry afterwards rather than left for the next test to trip over.
  test "register goes through the module and returns the module" do
    Dexpace::Transport.swap(:override) do
      assert_same(Dexpace::Transport, Dexpace::Transport.register(:probe, -> { :p }, core: CORE))
      assert_includes(Dexpace::Transport.registered_keys, :probe)
    end
  ensure
    forget(Dexpace::Transport, :probe)
  end

  test "an options-ignoring transport behaves identically with and without options" do
    transport = OptionsIgnoringTransport.new(:response)
    populated = Dexpace::RequestOptions.builder.tap do |builder|
      builder.timeout = 2.5
      builder.max_retries = 7
    end.build

    refute_equal(Dexpace::RequestOptions::EMPTY, populated, "the two calls really differ")

    assert_equal(
      transport.call(:request, Dexpace::RequestOptions::EMPTY, nil),
      transport.call(:request, populated, nil),
      "SEAM-11: options are inert immutable data, so ignoring them is not reading them",
    )
  end

  # SEAM-12 is a property of an implementation and phase 2 ships none; what the seam owes is that
  # nothing forces per-request state onto shared storage. The fake keeps every call in a local and
  # returns everything it produces, and this is the harness phase 8's adapters inherit.
  test "a conforming transport survives concurrent calls with no cross-talk" do
    transport = ->(request, _options, _cancellation) { request }
    results = ::Queue.new

    Array.new(32) { |i| ::Thread.new { results << transport.call(i, nil, nil) } }.each(&:join)

    seen = []
    seen << results.pop until results.empty?

    assert_equal((0...32).to_a, seen.sort)
  end

  test "async_over requires a caller-supplied executor and refuses anything without #post" do
    error = assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Transport.async_over(FakeTransport.new, executor: Object.new)
    end

    assert_match(/no default/, error.message, "SEAM-18: there is intentionally no default executor")
  end

  test "async_over refuses a non-conforming transport" do
    assert_raises(Dexpace::InvalidArgumentError) do
      Dexpace::Transport.async_over(Object.new, executor: InlineExecutor.new)
    end
  end

  test "ClosedError is the documented post-close failure mode" do
    assert_operator(Dexpace::ClosedError, :<, ::StandardError)
    assert_operator(Dexpace::ClosedError, :<, Dexpace::Error)
  end

  private

  # Removes a key from a seam's private registry after a test that had to register one: the
  # registry keeps registrations across a swap by design, and the module is process-global.
  def forget(seam, key)
    registry = seam.const_get(:REGISTRY, false)
    state = registry.instance_variable_get(:@state)
    registry.instance_variable_set(:@state, state.with(factories: state.factories.except(key)))
  end
end
