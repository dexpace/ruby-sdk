# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "minitest/autorun"
require "rubocop"

Dir[File.expand_path("../cops/**/*.rb", __dir__)].each { |file| require file }

# The Minitest equivalent of RuboCop::RSpec::ExpectOffense: parse a source string, run one cop
# over it through a Commissioner, and assert on the offenses it reported.
class CopCase < Minitest::Test
  # The same floor .rubocop.yml targets (NFR-10), so a cop is tested against the syntax it will
  # actually meet rather than against the development interpreter's.
  TARGET_RUBY = 3.2

  def self.test(name, &)
    define_method("test_: #{name}", &)
  end

  def offenses_for(cop_class, source, path: "lib/dexpace/example.rb")
    config = RuboCop::Config.new({ "AllCops" => { "TargetRubyVersion" => TARGET_RUBY } }, "/")
    cop = cop_class.new(config)
    processed = RuboCop::ProcessedSource.new(source, TARGET_RUBY, path)
    commissioner = RuboCop::Cop::Commissioner.new([cop], [], raise_error: true)

    commissioner.investigate(processed).offenses
  end

  def assert_offense(cop_class, source, message_fragment)
    found = offenses_for(cop_class, source)

    refute_empty(found, "expected #{cop_class} to register an offense on:\n#{source}")
    assert_includes(found.map(&:message).join("\n"), message_fragment)
  end

  def assert_no_offense(cop_class, source)
    assert_empty(offenses_for(cop_class, source).map(&:message))
  end
end
