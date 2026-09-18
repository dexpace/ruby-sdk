# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../../test_helper"

# R11, OBS-20: phase 5c holds no sink, reads no log level and references no Event, Logger or
# Keys -- the structural half of OBS-34's "span lifecycle AND metric recording run on every
# request independent of the log level" that makes 5b's own test at level `none` writable.
# OBS-34 is 5b's ID and is NOT discharged here; the two are named as two so neither document
# mistakes the other's mechanism for the whole.
#
# A subprocess, because the in-process suite has already loaded the whole tree through
# `require "dexpace"` and cannot un-define a constant. The assertion is written against the
# FILE LIST and not the entry point, deliberately: once phase 5b lands, `require "dexpace"`
# defines Event, and the guard against a 5c file acquiring a dependency on the logging half is
# that THESE ten files, loaded alone, do not. The interpreter is this process's own
# (RbConfig.ruby) and not `bundle exec`: core requires no gem, so the subprocess needs no
# bundle and runs identically on every matrix row. `require`, not `require_relative`: the
# latter has no stable basepath from `-e` across the supported range.
class DexpaceInstrumentationIndependenceTest < DexpaceTestCase
  GEM_ROOT = File.expand_path("../../..", __dir__)

  # no_span and no_tracer are required BEFORE bundle, and bundle requires them back: Bundle.build
  # defaults `span:` to NO_SPAN and NONE = build(...) runs at load, so entering bundle.rb first
  # raises `uninitialized constant Dexpace::Instrumentation::Bundle::NO_SPAN`. The order is
  # lib/dexpace.rb's and this list must keep it.
  FILES = %w[
    diagnostics trace_id_flavour no_span no_tracer bundle scope tracing meter http_tracer
    callable_adapter
  ].freeze

  PROGRAM = <<~RUBY.freeze
    #{FILES.map { |file| %(require "./lib/dexpace/instrumentation/#{file}") }.join("\n")}

    %i[Event Logger Keys Events HTTPLogging Step].each do |name|
      raise "5c must not load 5b's #{name}" if Dexpace::Instrumentation.const_defined?(name, false)
    end
    raise "5c must not load 5a's Configuration" if Dexpace.const_defined?(:Configuration, false)

    span = Dexpace::Instrumentation::NO_SPAN
    value = Dexpace::Instrumentation::Tracing.with_span(span) do
      Dexpace::Instrumentation::Tracing.with_correlated_span(
        span, Dexpace::Instrumentation::Bundle::NONE
      ) do
        meter = Dexpace::Instrumentation::NO_METER
        meter.create_counter("test").add(1)
        meter.create_histogram("test").record(1.5)
        Dexpace::Instrumentation::NULL.operation_started(:ctx)
        Dexpace::Instrumentation::TraceIdFlavour::W3C.generate_trace_id.size
      end
    end
    raise "tracing and metrics did not run: \#{value.inspect}" unless value == 32

    puts Dexpace::Instrumentation.constants(false).sort.join(" ")
    puts "OK"
  RUBY

  EXPECTED_CONSTANTS = %w[
    Bundle CallableAdapter Diagnostics HTTPTracer NO_METER NO_SCOPE NO_SPAN NO_TRACER
    NO_TRACER_FACTORY NULL Scope TraceIdFlavour Tracing
  ].freeze

  # `err: %i[child out]` is load-bearing: without it a subprocess failure arrives as an empty
  # `out` and an assertion that says nothing about why.
  test "R11: the ten 5c files load and run tracing and metrics with Event undefined" do
    out = IO.popen(
      [::RbConfig.ruby, "-w", "-e", PROGRAM], err: %i[child out], chdir: GEM_ROOT, &:read
    )

    assert_equal("#{EXPECTED_CONSTANTS.join(" ")}\nOK\n", out)
  end
end
