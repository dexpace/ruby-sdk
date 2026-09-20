# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"
require "dexpace"

# XCUT-4 branch (b): "A transport error MUST report itself as always-retryable at the error
# level." TRANSPORT-20: the canonical retryable transport failure. P3-3: a sibling of
# Dexpace::StreamError inside ::IOError, never a subclass, because a stream-contract violation
# must not claim to be always-retryable. P6-4: the class every phase-8 adapter wraps a bare stdlib
# I/O or timeout error into, so RETRY-2's capability query classifies it retryable.
#
# No `net/http` is required here: core embeds no concrete transport (SEAM-1/SEAM-2) and this suite
# must not either, so the wrapped-cause case uses a plain StandardError.
class DexpaceTransportErrorTest < DexpaceTestCase
  test "is an IOError and includes the module error root" do
    assert_operator(Dexpace::TransportError, :<, ::IOError)
    assert_operator(Dexpace::TransportError, :<, Dexpace::Error)
    assert_kind_of(Dexpace::Error, Dexpace::TransportError.new("boom"))
  end

  test "P3-3: is a sibling of StreamError, never its ancestor or descendant" do
    refute_operator(Dexpace::TransportError, :<, Dexpace::StreamError)
    refute_operator(Dexpace::StreamError, :<, Dexpace::TransportError)
  end

  test "XCUT-4 (b): reports retryable, unconditionally, with no keyword that can override it" do
    assert_predicate(Dexpace::TransportError.new("boom"), :retryable?)
    assert_predicate(Dexpace::TransportError.new("boom", phase: :read), :retryable?)
    refute_includes(
      Dexpace::TransportError.instance_method(:initialize).parameters.map(&:last), :retryable,
      "XCUT-4 (b) says always; a retryable: keyword would be a way to say otherwise",
    )
  end

  test "RETRY-2's capability query, over the cause chain, classifies it retryable" do
    assert(Dexpace::Resilience::Policy.throwable_retryable?(Dexpace::TransportError.new("boom")))
    wrapped = ::RuntimeError.new("outer")
    wrapped.define_singleton_method(:cause) { Dexpace::TransportError.new("inner") }

    assert(Dexpace::Resilience::Policy.throwable_retryable?(wrapped))
  end

  test "carries the phase the failure occurred in, for diagnostics only" do
    error = Dexpace::TransportError.new("boom", phase: :read)

    assert_equal(:read, error.phase)
    assert_nil(Dexpace::TransportError.new("boom").phase)
  end

  test "has a default message and carries a wrapped error's #cause the way Ruby always does" do
    assert_equal("a transport failure occurred", Dexpace::TransportError.new.message)
    wrapped = begin
      raise ::StandardError, "slow"
    rescue ::StandardError
      begin
        raise Dexpace::TransportError.new("wrapped", phase: :read)
      rescue Dexpace::TransportError => error
        error
      end
    end

    assert_instance_of(::StandardError, wrapped.cause)
    assert_equal("slow", wrapped.cause.message)
    assert_equal(:read, wrapped.phase)
  end

  test "P4-12: carries the suppressed trail like every other core error" do
    error = Dexpace::TransportError.new("primary")
    Dexpace.attach_suppressed(error, ::IOError.new("close failed"))

    assert_equal(["close failed"], Dexpace.suppressed(error).map(&:message))
  end
end
