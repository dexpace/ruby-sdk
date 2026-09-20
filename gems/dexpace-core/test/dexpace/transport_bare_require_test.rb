# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/bare_require"
require "dexpace"

# SEAM-1, SEAM-2, SEAM-6: the properties of the Transport seam that hold on a BARE
# `require "dexpace"` and on nothing else -- an empty registry, the zero-candidate SeamError that
# follows from one, and a swap or an install that leaves nothing resolved behind it. Each runs in
# a fresh process: `rake test:gems` runs every gem's suite in one process, and since phase 8a
# `dexpace-transport-net_http`'s entry file registers its factory under :net_http the moment it
# is required (design §3.6's require-time registration), so in that process the registry is NOT
# empty and #resolve builds an adapter instead of raising. The in-process form was the pin phase
# 8a's registration invalidated; transport_test.rb keeps the in-process halves. Phases 8b and 8c
# meet the same on AsyncTransport and can reuse this shape. No lib/ mirror: it asserts the
# process, not a file.
class DexpaceTransportBareRequireTest < DexpaceTestCase
  include BareRequire

  test "the registry starts empty, so SEAM-1 holds on a bare require" do
    assert_equal("[]", bare_require("print Dexpace::Transport.registered_keys.inspect"))
  end

  test "the zero-candidate error names no transport provider gem (SEAM-2)" do
    message = bare_require(<<~RUBY)
      begin
        Dexpace::Transport.resolve
        print "resolved"
      rescue Dexpace::SeamError => error
        print error.message
      end
    RUBY

    assert_match(/no transport provider is registered/, message)
    refute_match(%r{net_http|async_http|net/http}i, message, "SEAM-2")
  end

  test "after a swap block nothing is resolved again (SEAM-6)" do
    out = bare_require(<<~RUBY)
      t = ->(_request, _options, _cancellation) { :response }
      Dexpace::Transport.swap(t) do
        abort("the override was not resolved") unless Dexpace::Transport.resolve.equal?(t)
      end
      begin
        Dexpace::Transport.resolve
        print "resolved after the block"
      rescue Dexpace::SeamError
        print "SeamError"
      end
    RUBY

    assert_equal("SeamError", out)
  end

  test "an install inside a swap block is restored with it, leaving nothing resolved" do
    out = bare_require(<<~RUBY)
      i = ->(_request, _options, _cancellation) { :installed }
      Dexpace::Transport.swap(:override) { Dexpace::Transport.install(i) }
      begin
        Dexpace::Transport.resolve
        print "resolved after the block"
      rescue Dexpace::SeamError
        print "SeamError"
      end
    RUBY

    assert_equal("SeamError", out)
  end
end
