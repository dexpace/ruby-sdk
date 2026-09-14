# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "minitest/autorun"

# The base every suite in this repository inherits.
#
# Minitest does not ship `test "..." do`; ActiveSupport does, and there is no Rails here, so it
# is defined below. The description stays a freeform string in --verbose output and in CI logs,
# and the generated method name still begins with `test_`, which keeps Minitest/TestMethodName
# satisfied (styleguide 11.1).
class DexpaceTestCase < Minitest::Test
  # NFR-6: a warning raised by code under test fails the test that triggered it, with the file
  # and line. This catches nothing emitted before this file loads -- see the stderr scan in
  # tools/suite_runner.rb, which is the other half.
  module FatalWarnings
    def warn(message, category: nil)
      raise "warning treated as an error (NFR-6): #{message.strip}" \
            "#{" [#{category}]" unless category.nil?}"
    end
  end
  Warning.singleton_class.prepend(FatalWarnings)

  def self.test(name, &)
    define_method("test_: #{name}", &)
  end

  # NFR-6 / XCUT-11: neither half of warnings-as-errors can see a thread die. A thread that
  # terminates with an exception reports on $stderr directly -- Thread#report_on_exception does
  # not route through Warning.warn, and its line does not contain `warning:` -- so a test that
  # leaks one produces noise no gate reads. Counting threads across the test catches the leak
  # itself. A suite that must outlive a test with a running thread overrides `setup` to say why;
  # the assertion is never dropped.
  def setup
    super
    @dexpace_threads_before = ::Thread.list.size
  end

  def teardown
    super

    assert_equal(
      @dexpace_threads_before, ::Thread.list.size,
      "#{self.class}##{name} leaked a thread (NFR-6, XCUT-11): every thread a test starts is " \
      "joined before it returns",
    )
  end

  # A bounded property-style sample (styleguide 11.7). The iteration count is a literal, the
  # generator is bounded, and the seed is printed on failure so the counterexample sequence is
  # reproducible. No generator gem: the styleguide's own examples are hand-rolled `rand` loops.
  def sample(count: 64, seed: 20_260_905)
    rng = Random.new(seed)
    count.times do |index|
      yield rng
    rescue Minitest::Assertion => error
      raise error.class, "#{error.message}\n(sample #{index} of #{count}, seed #{seed})"
    end
  end
end
