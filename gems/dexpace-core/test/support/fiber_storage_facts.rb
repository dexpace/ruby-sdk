# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The two fiber-storage facts phase 5c found NOT uniform across the supported range, probed once
# per process on the interpreter that is running, so every suite that asserts against them
# asserts what this Ruby does rather than what 3.4.10 did (measured 2026-09-17 on 3.2.11, 3.3.12,
# 3.4.10 and 4.0.6; tracing_matrix_facts_test.rb pins the version boundaries):
#
# - `Fiber[:k] = nil` DELETES the key on 3.3 and later, and on the 3.2 floor leaves it present
#   with a nil value -- and 3.2 offers no other removal than the warned whole-map
#   `Fiber#storage=`. So OBS-23's "remove it if previously unset" is a removal on 3.3+ and a
#   nil-valued key on 3.2, which `Fiber[]` reads identically and OBS-10's "keys with null values
#   MUST be skipped" folds identically (P5-49, and the as-built row P5-72 for the floor half).
# - `Fiber["k"]` and `Fiber["k"] = v` intern a String key on 3.4 and later, and raise TypeError on
#   3.2 and 3.3 -- so a Symbol is the one key spelling every row accepts (R11).
#
# The probe keys are namespaced under `dexpace.` so nothing OBS-10 folds can collide with them;
# on the floor the nil-valued probe key stays in the main fiber's storage, which is exactly the
# state the first fact describes and is harmless for the reason it gives.
module FiberStorageFacts
  NIL_ASSIGNMENT_DELETES = begin
    ::Fiber[:"dexpace.probe.nil"] = 1
    ::Fiber[:"dexpace.probe.nil"] = nil
    !::Fiber.current.storage.key?(:"dexpace.probe.nil")
  end

  STRING_KEY_INTERNED = begin
    ::Fiber["dexpace.probe.string"] = 1
    ::Fiber[:"dexpace.probe.string"] = nil
    true
  rescue ::TypeError
    false
  end

  # OBS-23's "remove it if previously unset", asserted the way this interpreter can honour it:
  # absent where `= nil` deletes, present-with-nil on the floor -- and never the pushed value.
  def assert_diagnostic_key_removed(key)
    if NIL_ASSIGNMENT_DELETES
      refute(::Fiber.current.storage.key?(key), "#{key.inspect} should have been removed")
    else
      assert(::Fiber.current.storage.key?(key), "3.2 retains #{key.inspect} with a nil value")
      assert_nil(::Fiber[key], "#{key.inspect} should read back as nil on the 3.2 floor")
    end
  end

  # A key nothing set: absent where `= nil` deletes; on the floor absent or nil-valued, because
  # any earlier teardown's `= nil` in the same fiber has already made it the latter.
  def assert_diagnostic_key_unset(key)
    assert_nil(::Fiber[key], "#{key.inspect} should be unset")
    refute(::Fiber.current.storage.key?(key), "#{key.inspect} present") if NIL_ASSIGNMENT_DELETES
  end
end
