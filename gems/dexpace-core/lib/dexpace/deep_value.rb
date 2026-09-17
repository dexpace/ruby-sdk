# frozen_string_literal: true
# SPDX-License-Identifier: MIT

module Dexpace
  # Deep value equality and the hash that matches it (CFG-33, CFG-34): content-based, recursive
  # over Arrays and Hashes, null-safe with null hashing to zero, and with floating-point array
  # semantics Ruby's own `==`, `eql?` and `#hash` all get wrong for this purpose -- NaN equals NaN
  # (both `==` and `eql?` say no), +0.0 and -0.0 are unequal (`==` and `eql?` say yes, and
  # `0.0.hash == (-0.0).hash`), and an Integer array is not a Float array of the same values
  # (`[1] == [1.0]` is true). Element kind is the live reading of CFG-34's "distinct array kinds"
  # in a language with one Array; the boxed-versus-primitive CONTAINER clause has no Ruby
  # manifestation and stays inapplicable per §11.15, not extended (P5-14).
  #
  # The hash side is where the work is. Float#hash digests the bit pattern, so two NaNs hash
  # alike only when their payloads agree: 0.0/0.0 and -(0.0/0.0) differ in the sign bit and hash
  # apart, while .equal? calls them equal. Every NaN therefore folds to ONE seed, the two signed
  # zeros to two distinct seeds, and no float's contribution comes from Float#hash on a value
  # this module classifies specially -- which is CFG-33's "equals and hashCode MUST be mutually
  # consistent" and CFG-34's "hashing MUST match that equality" as one rule.
  #
  # Cycle-safe, which no CFG ID asks for (P5-15): a naive recursion over two self-referential
  # arrays raises SystemStackError where Array#== survives through Ruby's own guard, and a helper
  # less robust than the language on the one input the language handles is a regression. The
  # guard is identity-keyed, `{}.compare_by_identity`, the mechanism Dexpace.each_cause uses.
  #
  # A private_constant on Dexpace (R4): it has no caller anywhere in v1 and exists to satisfy
  # CFG-33's conformance clause; promoting it later is a widening NFR-4 permits, the reverse is a
  # break. Reachable by bare name from any file that reopens `module Dexpace` in the full nesting
  # form, which is how configuration_test.rb and a later dexpace-conformance suite drive it.
  module DeepValue
    extend self

    # One seed for every NaN, whatever its payload.
    NAN_HASH = 0x7ff8_0000_0000_0000.hash
    # +0.0's seed, Ruby's own.
    POSITIVE_ZERO_HASH = 0.0.hash
    # -0.0's seed, derived from the positive one so the pair can never coincide (Ruby's own is
    # equal to +0.0's).
    NEGATIVE_ZERO_HASH = ~POSITIVE_ZERO_HASH
    # What a container contributes when it is reached again through itself.
    CYCLE_HASH = 0xdead_beef.hash

    # @return [Boolean] whether the two values are deeply equal under CFG-33 and CFG-34
    def equal?(left, right)
      visited = {} #: Hash[untyped, Hash[untyped, bool]]
      equal_rec?(left, right, visited.compare_by_identity)
    end

    # @return [Integer] a hash consistent with .equal?
    def hash(value)
      stack = {} #: Hash[untyped, bool]
      hash_rec(value, stack.compare_by_identity)
    end

    private

    def equal_rec?(left, right, visited)
      return true if left.equal?(right)
      return false if left.nil? || right.nil?
      return numbers_equal?(left, right) if left.is_a?(::Numeric)
      return containers_equal?(left, right, visited) if left.is_a?(::Array) || left.is_a?(::Hash)

      left == right
    end

    # Element-kind distinctness: eql? and never ==, which calls 1 and 1.0 equal (P5-14); two
    # Floats take the CFG-34 branch.
    def numbers_equal?(left, right)
      return floats_equal?(left, right) if left.is_a?(::Float) && right.is_a?(::Float)

      left.eql?(right)
    end

    # rubocop:disable Lint/FloatComparison -- the exact comparisons ARE the point: CFG-34 fixes
    # float equality bit for bit, not within a tolerance. NaN equals NaN; +0.0 and -0.0 are told
    # apart by 1.0 / x (Infinity against -Infinity).
    def floats_equal?(left, right)
      return true if left.nan? && right.nan?
      return (1.0 / left) == (1.0 / right) if left.zero? && right.zero?

      left == right
    end
    # rubocop:enable Lint/FloatComparison

    def containers_equal?(left, right, visited)
      same_kind = left.is_a?(::Array) ? right.is_a?(::Array) : right.is_a?(::Hash)
      return false unless same_kind && left.size == right.size
      return true if comparing?(visited, left, right)

      case left
      when ::Array then arrays_equal?(left, right, visited)
      else hashes_equal?(left, right, visited)
      end
    end

    def arrays_equal?(left, right, visited)
      left.each_with_index.all? { |element, index| equal_rec?(element, right[index], visited) }
    end

    def hashes_equal?(left, right, visited)
      left.all? { |key, value| right.key?(key) && equal_rec?(value, right[key], visited) }
    end

    # The guard is keyed by the PAIR, never by each side independently. Two separate sets say
    # "left was seen, and separately right was seen", which answers true for a pair that was
    # never compared: [u, v, u] against [m, n, n] with u and n unequal is a false positive on the
    # third element. One identity-keyed map of identity-keyed maps says "left is already being
    # compared against right" -- the co-inductive answer for a cycle, and a sound memoisation
    # otherwise, because a false result leaves #all? at once and never reaches a second read.
    def comparing?(visited, left, right)
      fresh = {} #: Hash[untyped, bool]
      partners = (visited[left] ||= fresh.compare_by_identity)
      return true if partners[right]

      partners[right] = true
      false
    end

    # `stack` is a recursion STACK and not a visited set: the entry is removed on the way out. A
    # set that never unwinds hashes [u, u] differently from an equal [m, n], because the second u
    # would fold to CYCLE_HASH -- CFG-33's mutual consistency broken by the guard meant to protect
    # it. Array#hash unwinds the same way.
    def hash_rec(value, stack)
      return 0 if value.nil? # CFG-33: "two nulls are equal; null hashes to zero"
      return float_hash(value) if value.is_a?(::Float)
      return CYCLE_HASH if stack[value]

      case value
      when ::Array then array_hash(value, stack)
      when ::Hash then hash_hash(value, stack)
      else value.hash
      end
    end

    def float_hash(value)
      return NAN_HASH if value.nan?
      return (1.0 / value).positive? ? POSITIVE_ZERO_HASH : NEGATIVE_ZERO_HASH if value.zero?

      value.hash
    end

    def array_hash(value, stack)
      stack[value] = true
      value.inject(17) { |acc, element| (acc * 31) + hash_rec(element, stack) }
    ensure
      stack.delete(value)
    end

    # Order-independent, as Hash#== is: the per-entry terms are summed rather than folded.
    def hash_hash(value, stack)
      stack[value] = true
      value.inject(19) { |acc, (key, entry)| acc + (key.hash ^ hash_rec(entry, stack)) }
    ensure
      stack.delete(value)
    end
  end

  private_constant :DeepValue
end
