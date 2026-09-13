#!/usr/bin/env ruby
# frozen_string_literal: true

# SPDX-License-Identifier: MIT
# .claude/skills/housekeeping/test/run.rb
#
# The whole suite, in one command and with no dependency beyond the bundled Minitest:
#
#   ruby .claude/skills/housekeeping/test/run.rb
#   ruby .claude/skills/housekeeping/test/run.rb -n /guard/     # Minitest flags pass through

require 'minitest/autorun'

Dir.glob(File.join(__dir__, '*_test.rb')).sort.each { |file| require file }
