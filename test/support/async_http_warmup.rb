# frozen_string_literal: true
# SPDX-License-Identifier: MIT

# Ruby 4.0's fiber-scheduler `io_read` hook hands io-event an `IO::Buffer`, and CRuby emits the
# once-per-process `warning: IO::Buffer is experimental and both the Ruby and C interface may
# change in the future!` the first time one is allocated -- with or without `-w`, because the
# experimental category is on by default -- so on the 4.0 row the FIRST `IO#read_nonblock` under
# an Async reactor warns, from inside the exchange's own fiber. Measured on 4.0.6 (any read_nonblock
# inside `Sync`, `<internal:io>:63`); 3.3.12 and 3.4.10 take a path that allocates none. Nothing
# in the SDK allocates one: it is the interpreter's own scheduler machinery.
#
# DexpaceTestCase turns every Warning.warn into an error, so the first test to send a request on
# 4.0.6 would fail with a warning it did not cause, wrapped as a transport failure. One buffer
# here, at this gem's test-helper load, with the experimental category off for exactly that
# allocation, spends the once-only warning silently and leaves `Warning[:experimental]` as it
# was -- the same category of arrangement as net_http_warmup.rb's Timeout thread (P8-62), and
# not the SDK's: the gem's lib/ sets no `Warning[]` and a consumer on 4.0 sees the interpreter's
# one warning line on their first request, which the gem's README says.
module AsyncHTTPWarmup
  # @return [nil]
  def self.run
    was = Warning[:experimental]
    Warning[:experimental] = false
    ::IO::Buffer.new(1).free
    nil
  ensure
    Warning[:experimental] = was
  end
end

AsyncHTTPWarmup.run
