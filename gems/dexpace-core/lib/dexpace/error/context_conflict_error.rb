# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../error"

module Dexpace
  # CTX-8's reject-on-duplicate loser: a ContextStore#put lost the race for a call key another
  # registration already occupies.
  #
  # Not Dexpace::InvalidArgumentError, deliberately. The caller passed nothing invalid -- it lost a
  # race -- and a caller that cannot tell those two apart cannot retry correctly. The message
  # names the key because CTX-8's own words are "an error whose message identifies the key", and
  # the key is carried as a member too, so a caller reads it rather than parsing the message. The
  # fourth error in phase 2's shape: `< ::StandardError` with the Dexpace::Error marker included.
  class ContextConflictError < ::StandardError
    include Dexpace::Error

    # @return [String] the call key the losing registration tried to install under
    attr_reader :call_key

    # The one-argument shape is what `raise Dexpace::ContextConflictError, key` needs: Ruby hands
    # the second argument of `raise` to the class's constructor, so the key travels as itself.
    def initialize(call_key)
      @call_key = call_key
      super("a context is already registered under call key #{call_key.inspect} (CTX-8)")
    end
  end
end
