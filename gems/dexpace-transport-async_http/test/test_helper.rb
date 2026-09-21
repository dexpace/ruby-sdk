# frozen_string_literal: true
# SPDX-License-Identifier: MIT

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

# The workspace's shared test base. This reaches out of the gem directory into the repository's
# own test support, which is not the cross-gem require_relative styleguide 12.6 forbids -- that
# rule is about reaching into another *gem's* internals.
require_relative "../../../test/support/dexpace_test_case"
# The one IO::Buffer that spends Ruby 4.0's once-per-process experimental warning outside every
# test, before the test base's fatal-warning hook can see it (see the file). Not net_http_warmup:
# this gem starts no Net::HTTP, and the reactor starts no thread.
require_relative "../../../test/support/async_http_warmup"
