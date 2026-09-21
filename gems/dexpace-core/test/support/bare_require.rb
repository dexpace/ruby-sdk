# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require "open3"
require "rbconfig"

# A fresh interpreter running a program after a bare `require "dexpace"`, with bundler's RUBYOPT
# cleared so nothing but core's own tree loads (context_store_config_test.rb's idiom). The shape
# every "property of a bare require" test shares since phase 8a: `rake test:gems` runs every
# gem's suite in one process, and an adapter's entry file registers its factory under its seam
# the moment it is required (design §3.6), so in that process a seam's registry is not empty and
# an in-process assertion of emptiness is the pin the first adapter invalidated. The child
# requires core alone, which is the property SEAM-1 states.
module BareRequire
  CORE_LIB = File.expand_path("../../lib", __dir__)

  # @param program [String] Ruby run after `require "dexpace"`
  # @return [String] the child's stdout; the child must exit 0 and write nothing to stderr
  def bare_require(program)
    out, err, status = Open3.capture3(
      { "RUBYOPT" => nil }, RbConfig.ruby, "-w", "-W:deprecated", "-I", CORE_LIB, "-e",
      "require \"dexpace\"; #{program}",
    )

    assert_predicate(status, :success?, err)
    assert_empty(err, "a bare require must be silent under -w")
    out
  end
end
