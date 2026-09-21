# frozen_string_literal: true
# SPDX-License-Identifier: MIT

require_relative "../test_helper"
require_relative "../support/bare_require"
require "dexpace"

# SEAM-1, SEAM-2, SEAM-6 on the AsyncTransport seam: the properties that hold on a BARE
# `require "dexpace"` and on nothing else -- an empty registry that is not the sync seam's, the
# zero-candidate SeamError that follows from one, and a swap or an install that leaves nothing
# resolved behind it. Each runs in a fresh process, for the reason transport_bare_require_test.rb
# gives about the sync seam since phase 8a: since phase 8c `dexpace-transport-async_http`'s entry
# file registers its factory under :async_http the moment it is required (design §3.6), so in
# the one `rake test:gems` process the registry is NOT empty and #resolve builds an adapter
# instead of raising. The in-process form was the pin phase 8c's registration invalidated;
# async_transport_test.rb keeps the in-process halves. No lib/ mirror: it asserts the process,
# not a file.
class DexpaceAsyncTransportBareRequireTest < DexpaceTestCase
  include BareRequire

  test "the registry starts empty and is not the sync seam's (SEAM-1, P2-1)" do
    out = bare_require(<<~RUBY)
      print Dexpace::AsyncTransport.registered_keys.inspect
      Dexpace::Transport.swap(->(_r, _o, _c) { :sync }) do
        begin
          Dexpace::AsyncTransport.resolve
          print " resolved through the sync seam"
        rescue Dexpace::SeamError
          print " SeamError"
        end
      end
    RUBY

    assert_equal("[] SeamError", out)
  end

  test "the zero-candidate error names this seam and no gem (SEAM-2)" do
    message = bare_require(<<~RUBY)
      begin
        Dexpace::AsyncTransport.resolve
        print "resolved"
      rescue Dexpace::SeamError => error
        print error.message
      end
    RUBY

    assert_match(/no async transport provider is registered/, message)
    assert_match(/Dexpace::AsyncTransport\.install/, message)
    refute_match(%r{async_http|net_http|async/http}i, message, "SEAM-2")
  end

  test "after a swap block nothing is resolved again (SEAM-6)" do
    out = bare_require(<<~RUBY)
      t = ->(_request, _options, _cancellation) { :future }
      Dexpace::AsyncTransport.swap(t) do
        abort("the override was not resolved") unless Dexpace::AsyncTransport.resolve.equal?(t)
      end
      begin
        Dexpace::AsyncTransport.resolve
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
      Dexpace::AsyncTransport.swap(:override) { Dexpace::AsyncTransport.install(i) }
      begin
        Dexpace::AsyncTransport.resolve
        print "resolved after the block"
      rescue Dexpace::SeamError
        print "SeamError"
      end
    RUBY

    assert_equal("SeamError", out)
  end
end
