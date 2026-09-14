# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Gate fixture: a gemspec that reads the clock at build time, so no epoch can make two builds of
# it agree. This is the input that turns the gates:reproducible TASK red.
Gem::Specification.new do |spec|
  spec.name = "clock_dependent"
  spec.version = "0.0.0"
  spec.authors = ["dexpace"]
  spec.summary = "Gate fixture: built at #{Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)}."
  spec.files = Dir.glob("lib/**/*.rb", base: __dir__).sort
  spec.require_paths = ["lib"]
end
