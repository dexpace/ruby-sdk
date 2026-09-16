# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# The view-retention measurement, not a test: it prints numbers and asserts nothing, because what
# 3a asked for is a measurement on phase 3b's actual BODY-23 drain rather than a redesign of phase
# 3a's view registry. Run it by hand, record the table in phase 3b's checklist beside its plan's
# decision 5, and delete nothing from 3a.
#
#   bundle exec ruby -w -Igems/dexpace-core/lib tools/measure_view_retention.rb
#
# It lives in tools/ and not in test/, so it never runs in CI and never becomes a timing-sensitive
# test that fails on a loaded machine. Every BODY-23 read is one `#source` call on a fits-cap
# ResponseLoggingBody, which hands out a fresh #peek view of the captured buffer; the view stays
# registered with the buffer until the caller closes it, and deregistration is an Array#delete.
#
# `benchmark` is a bundled gem from Ruby 4.0 and is deliberately NOT required: this tool runs
# under the repository's own Gemfile, where it is not declared, so Process.clock_gettime is the
# clock. The require allowlist scans gems' lib/ and never reaches tools/, but a tool that needed a
# bundled gem would be a tool that failed on the development Ruby.

require "dexpace"

def elapsed
  before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  yield
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - before
end

def wrapper(bytes)
  delegate = Dexpace::ResponseBody.new(source: Dexpace::IO::BufferedSource.of_bytes(bytes))
  Dexpace::ResponseLoggingBody.new(delegate, preview_bytes: 64 * 1024)
end

def registry(wrapper)
  wrapper.instance_variable_get(:@buffer).instance_variable_get(:@dexpace_views)
end

puts "ruby #{RUBY_VERSION}"
puts "reads  registered  bytes_retained  read_s   close_all_s"
[1, 10, 100, 1_000, 10_000].each do |reads|
  subject = wrapper("x" * 4096)
  subject.snapshot
  views = nil
  taking = elapsed { views = Array.new(reads) { subject.source } }
  registered = registry(subject).length
  retained = views.sum { |view| view.instance_variable_get(:@dexpace_buffered) }
  closing = elapsed { views.each(&:close) }
  puts format("%<reads>6d %<registered>10d %<retained>15d %<taking>8.4f %<closing>12.4f",
              reads: reads, registered: registered, retained: retained, taking: taking,
              closing: closing,)
end

puts
puts "closing in REVERSE order (Array#delete scans from the front):"
[1_000, 10_000].each do |reads|
  subject = wrapper("x" * 4096)
  subject.snapshot
  views = Array.new(reads) { subject.source }
  reverse = elapsed { views.reverse_each(&:close) }
  puts format("%<reads>6d reverse close: %<reverse>.4f s", reads: reads, reverse: reverse)
end

puts
puts "views READ to the end before they are closed (one fill per read since 3a's R0-1 fix):"
subject = wrapper("x" * 4096)
subject.snapshot
views = Array.new(1_000) { subject.source }
reading = elapsed { views.each(&:read) }
retained = views.sum { |view| view.instance_variable_get(:@dexpace_buffered) }
puts format("  1000 views read to the end in %<reading>.4f s, %<retained>d bytes retained " \
            "across them afterwards", reading: reading, retained: retained,)
views.each(&:close)

puts
subject = wrapper("x" * 4096)
subject.snapshot
before = GC.stat(:total_allocated_objects)
2_000.times { subject.source }
after = GC.stat(:total_allocated_objects)
allocated = after - before
puts format("2000 reads allocated %<total>d objects (%<each>.1f per view)",
            total: allocated, each: allocated / 2000.0,)
