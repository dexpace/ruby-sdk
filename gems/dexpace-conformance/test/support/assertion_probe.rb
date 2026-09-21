# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "dexpace/conformance"

# The helpers the five assertion-group suites share: find an assertion by the id it carries, run
# it alone through the real runner against a given factory (a fresh case, torn down after), and
# assert the Result's status. An assertion is proven in BOTH directions -- it passes against a
# correct send and fails against the defect it was written for -- because an assertion that never
# raises proves nothing, and the real adapter's run cannot tell the difference.
module AssertionProbe
  Suite = Dexpace::Conformance::TransportSuite

  def find(id)
    Suite.assertions.find { |assertion| assertion.ids.include?(id) } ||

      flunk("no assertion carries #{id}")
  end

  def find_all(id)
    Suite.assertions.select { |assertion| assertion.ids.include?(id) }
  end

  def result_for(assertion, build:, borrow: nil)
    Suite.run(build: build, borrow: borrow, assertions: [assertion]).results.first
  end

  def assert_passes(assertion, build:, borrow: nil)
    result = result_for(assertion, build: build, borrow: borrow)

    assert_equal(:passed, result.status, "#{assertion.name}: #{result.detail}")
  end

  def assert_fails(assertion, build:, borrow: nil, matching: nil)
    result = result_for(assertion, build: build, borrow: borrow)

    assert_equal(:failed, result.status, "#{assertion.name}: #{result.detail}")
    assert_match(matching, result.detail.to_s) if matching
    result
  end

  def assert_vacuous(assertion, build:, matching: nil)
    result = result_for(assertion, build: build)

    assert_equal(:vacuous, result.status, "#{assertion.name}: #{result.detail}")
    assert_match(matching, result.detail.to_s) if matching
  end

  def raw(*defects)
    ->(**_settings) { RawWireTransport.new(*defects) }
  end
end
