# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../model"
require_relative "../error/invalid_argument_error"

module Dexpace
  class Configuration
    # The substitutable lookup seams (CFG-11): each is a frozen callable from key name to String?,
    # so a conformance test or an application supplies a hermetic lookup without touching the
    # process environment. ENVIRONMENT and NONE are the platform-backed pair CFG-13's empty
    # configuration is built over; .from_hash is the seam Dexpace.configure installs and what a
    # hermetic test builds.
    #
    # It is ENVIRONMENT and not ENV (P5-3): Sources::ENV would shadow Ruby's ::ENV for every bare
    # reference inside `module Dexpace; class Configuration; module Sources`, including the one in
    # its own body. A name chosen so the shadow never exists is better than a cop policing one.
    #
    # Reopens `class Configuration`, which configuration.rb declares and requires this file from;
    # it never appears in lib/dexpace.rb.
    module Sources
      # The host process environment, read by exact name. ENV[] returns a frozen String, a new
      # object each call, and "" for a present-but-empty variable: CFG-2's fall-through is the
      # chain's rule and not this seam's.
      ENVIRONMENT = ->(key) { ::ENV.fetch(key.to_s, nil) }.freeze

      # The seam that answers nil for every key: CFG-13's "no overrides, platform-backed seams"
      # on the property side, where the platform has nothing to read.
      NONE = ->(_key) {}.freeze

      # A hermetic seam over a copy of `map`, keys and values stringified, the copy frozen: later
      # mutation of the caller's map never reaches it.
      #
      # @param map [Hash] key -> value; a nil value is refused (CFG-37)
      # @return [Proc] a frozen callable from key name to String?
      # @raise [Dexpace::InvalidArgumentError] on an absent map, a non-Hash, or a nil value
      def self.from_hash(map)
        Model.required!("map", map)
        raise InvalidArgumentError, "map must be a Hash, got #{map.class}" unless map.is_a?(::Hash)

        table = {} #: Hash[String, String]
        map.each do |key, value|
          Model.required!("value for #{key.inspect}", value)
          table[key.to_s] = value.to_s
        end
        table.freeze
        ->(key) { table[key.to_s] }.freeze
      end
    end
  end
end
