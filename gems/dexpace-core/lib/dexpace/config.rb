# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "model"
require_relative "configuration"
require_relative "error/invalid_argument_error"

# The process-wide configuration slot (CFG-13): last-write-wins replacement, safe publication,
# defaulting to Configuration::EMPTY. Design §8.2 names exactly two of these three, .configure and
# .reset_config!; .configuration is the reader (P5-1, P5-2).
#
# The slot is one frozen reference swapped under a ::Thread::Mutex and read with no lock at all
# (concurrency-and-async/f414b864): the Configuration is frozen, so a reader that observes the
# reference observes it whole. The mutex is held across the assignment and across nothing else --
# never the caller's block, which runs before it is taken, and never a source callable -- so a
# configure block that itself reads Dexpace.configuration cannot deadlock on a non-reentrant,
# per-fiber-owned mutex. CFG-13 is last-write-wins and safe publication and NOTHING else: there is
# no listener, no observer and no fan-out here, and a change notification would be a new seam
# nothing asked for.
#
# The reader is a method and not a constant, because data-modeling/6accaff9 requires a mutable
# constant to be frozen at assignment and this slot is replaceable by design.
module Dexpace
  @config_mutex = ::Thread::Mutex.new
  @configuration = Configuration::EMPTY

  # The live process-wide configuration, read without a lock.
  #
  # @return [Dexpace::Configuration] a frozen snapshot
  def self.configuration
    @configuration
  end

  # Replaces the process-wide configuration with one derived from the live slot through the
  # block, then publishes it atomically. Last-write-wins: two configures in sequence leave the
  # second's result, with any property the first added still present unless the second replaced
  # it, because the builder is seeded from the live slot. A block that raises publishes nothing.
  #
  # @yieldparam builder [Dexpace::Configuration::Builder] seeded from the live configuration
  # @return [Dexpace::Configuration] the configuration now published
  # @raise [Dexpace::InvalidArgumentError] without a block -- CFG-37 names the global-config
  #   setter among the mutating operations that must fail fast rather than store a null
  def self.configure
    raise InvalidArgumentError, "configure block is required" unless block_given?

    builder = @configuration.new_builder
    yield builder
    built = builder.build
    @config_mutex.synchronize { @configuration = built }
  end

  # Restores Configuration::EMPTY. Public because testing/4ef070df requires every test to run
  # alone in any order, and a suite that mutates a process-wide slot without a restore cannot;
  # every test that calls .configure calls this in teardown.
  #
  # @return [Dexpace::Configuration] Configuration::EMPTY
  def self.reset_config!
    @config_mutex.synchronize { @configuration = Configuration::EMPTY }
  end
end
